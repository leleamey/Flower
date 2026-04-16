from datetime import datetime, timedelta
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel, EmailStr
from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, create_engine
from sqlalchemy.orm import Session, declarative_base, relationship, sessionmaker

DATABASE_URL = "postgresql://user:password@db:5432/ticketdb"
SECRET = "itsmsecret"
ALGORITHM = "HS256"
SLA_HOURS = {"P1": 4, "P2": 8, "P3": 24}

engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)
Base = declarative_base()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/login")


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, nullable=False, index=True)
    password = Column(String, nullable=False)
    role = Column(String, default="user", nullable=False)

    tickets = relationship("Ticket", back_populates="owner")


class Ticket(Base):
    __tablename__ = "tickets"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, nullable=False)
    description = Column(String, default="", nullable=False)
    priority = Column(String, nullable=False)
    status = Column(String, default="open", nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    owner_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    owner = relationship("User", back_populates="tickets")


Base.metadata.create_all(bind=engine)


class RegisterPayload(BaseModel):
    email: EmailStr
    password: str


class LoginPayload(BaseModel):
    email: EmailStr
    password: str


class TicketCreatePayload(BaseModel):
    title: str
    description: str = ""
    priority: str


class TicketUpdatePayload(BaseModel):
    status: str


app = FastAPI(title="ITSM Ticketing API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def build_token(user: User) -> str:
    payload = {
        "sub": user.email,
        "role": user.role,
        "exp": datetime.utcnow() + timedelta(hours=12),
    }
    return jwt.encode(payload, SECRET, algorithm=ALGORITHM)


def get_current_user(
    token: Annotated[str, Depends(oauth2_scheme)],
    db: Annotated[Session, Depends(get_db)],
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid token",
    )
    try:
        payload = jwt.decode(token, SECRET, algorithms=[ALGORITHM])
        email: str | None = payload.get("sub")
        if email is None:
            raise credentials_exception
    except JWTError as exc:
        raise credentials_exception from exc

    user = db.query(User).filter(User.email == email).first()
    if user is None:
        raise credentials_exception
    return user


@app.get("/health")
def health_check():
    return {"status": "ok", "service": "itsm-ticketing"}


@app.post("/register")
def register(payload: RegisterPayload, db: Session = Depends(get_db)):
    existing_user = db.query(User).filter(User.email == payload.email).first()
    if existing_user:
        raise HTTPException(status_code=409, detail="Email already exists")

    user = User(email=payload.email, password=pwd_context.hash(payload.password))
    db.add(user)
    db.commit()
    return {"message": "User registered successfully"}


@app.post("/login")
def login(payload: LoginPayload, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    if not user or not pwd_context.verify(payload.password, user.password):
        raise HTTPException(status_code=401, detail="Invalid login")

    token = build_token(user)
    return {"access_token": token, "token_type": "bearer", "role": user.role}


@app.get("/me")
def me(current_user: User = Depends(get_current_user)):
    return {"email": current_user.email, "role": current_user.role}


@app.post("/tickets")
def create_ticket(
    payload: TicketCreatePayload,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if payload.priority not in SLA_HOURS:
        raise HTTPException(status_code=400, detail="Priority must be P1, P2, or P3")

    ticket = Ticket(
        title=payload.title.strip(),
        description=payload.description.strip(),
        priority=payload.priority,
        owner_id=current_user.id,
    )
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    return {
        "id": ticket.id,
        "title": ticket.title,
        "description": ticket.description,
        "priority": ticket.priority,
        "status": ticket.status,
        "created_at": ticket.created_at,
    }


@app.get("/tickets")
def list_tickets(
    status_filter: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Ticket)
    if current_user.role != "admin":
        query = query.filter(Ticket.owner_id == current_user.id)
    if status_filter:
        query = query.filter(Ticket.status == status_filter)

    tickets = query.order_by(Ticket.created_at.desc()).all()
    return [
        {
            "id": t.id,
            "title": t.title,
            "description": t.description,
            "priority": t.priority,
            "status": t.status,
            "created_at": t.created_at,
            "owner_email": t.owner.email if t.owner else None,
        }
        for t in tickets
    ]


@app.patch("/tickets/{ticket_id}")
def update_ticket_status(
    ticket_id: int,
    payload: TicketUpdatePayload,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    ticket = db.query(Ticket).filter(Ticket.id == ticket_id).first()
    if ticket is None:
        raise HTTPException(status_code=404, detail="Ticket not found")

    if current_user.role != "admin" and ticket.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not allowed")

    ticket.status = payload.status
    ticket.updated_at = datetime.utcnow()
    db.commit()
    return {"message": "Ticket updated"}


@app.get("/sla")
def sla_dashboard(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Ticket)
    if current_user.role != "admin":
        query = query.filter(Ticket.owner_id == current_user.id)

    results = []
    now = datetime.utcnow()
    for ticket in query.all():
        target = ticket.created_at + timedelta(hours=SLA_HOURS[ticket.priority])
        results.append(
            {
                "id": ticket.id,
                "title": ticket.title,
                "priority": ticket.priority,
                "status": ticket.status,
                "sla_target": target,
                "breach": now > target and ticket.status != "resolved",
            }
        )
    return results
