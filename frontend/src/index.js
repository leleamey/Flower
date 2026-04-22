import React, { useEffect, useMemo, useState } from "react";
import ReactDOM from "react-dom/client";
import axios from "axios";
import "./styles.css";

const API_BASE_URL = process.env.REACT_APP_API_BASE_URL || "http://localhost:8000";

const api = axios.create({
  baseURL: API_BASE_URL,
});

function Badge({ value }) {
  return <span className={`badge badge-${value.toLowerCase()}`}>{value}</span>;
}

function App() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [token, setToken] = useState(localStorage.getItem("itsm_token") || "");
  const [tickets, setTickets] = useState([]);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [priority, setPriority] = useState("P2");
  const [statusFilter, setStatusFilter] = useState("");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState("");

  const headers = useMemo(
    () => ({ Authorization: `Bearer ${token}` }),
    [token]
  );

  const loadTickets = async () => {
    if (!token) return;
    setLoading(true);
    try {
      const query = statusFilter ? `?status_filter=${statusFilter}` : "";
      const response = await api.get(`/tickets${query}`, { headers });
      setTickets(response.data);
    } catch (error) {
      setMessage(error.response?.data?.detail || "Failed to load tickets");
    } finally {
      setLoading(false);
    }
  };

  const registerAndLogin = async () => {
    try {
      await api.post("/register", { email, password });
    } catch (error) {
      if (error.response?.status !== 409) {
        setMessage(error.response?.data?.detail || "Registration failed");
        return;
      }
    }

    try {
      const response = await api.post("/login", { email, password });
      const nextToken = response.data.access_token;
      setToken(nextToken);
      localStorage.setItem("itsm_token", nextToken);
      setMessage("Login successful");
    } catch (error) {
      setMessage(error.response?.data?.detail || "Login failed");
    }
  };

  const createTicket = async () => {
    if (!title.trim()) {
      setMessage("Ticket title is required");
      return;
    }
    try {
      await api.post(
        "/tickets",
        { title, description, priority },
        { headers }
      );
      setTitle("");
      setDescription("");
      await loadTickets();
      setMessage("Ticket created successfully");
    } catch (error) {
      setMessage(error.response?.data?.detail || "Unable to create ticket");
    }
  };

  const changeStatus = async (id, nextStatus) => {
    try {
      await api.patch(`/tickets/${id}`, { status: nextStatus }, { headers });
      await loadTickets();
    } catch (error) {
      setMessage(error.response?.data?.detail || "Unable to update status");
    }
  };

  const logout = () => {
    setToken("");
    localStorage.removeItem("itsm_token");
    setTickets([]);
  };

  useEffect(() => {
    loadTickets();
  }, [token, statusFilter]);

  return (
    <main className="app-shell">
      <header className="topbar">
        <div>
          <p className="eyebrow">Service Management Suite</p>
          <h1>ITSM Ticketing Center</h1>
        </div>
        {token ? (
          <button className="btn ghost" onClick={logout}>
            Logout
          </button>
        ) : null}
      </header>

      {!token ? (
        <section className="card auth-card">
          <h2>Access Portal</h2>
          <p>Register once and sign in to start managing incidents.</p>
          <div className="grid-2">
            <input
              className="input"
              placeholder="Work email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
            />
            <input
              className="input"
              type="password"
              placeholder="Password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </div>
          <button className="btn primary" onClick={registerAndLogin}>
            Register / Login
          </button>
        </section>
      ) : (
        <>
          <section className="card">
            <h2>Create Ticket</h2>
            <div className="grid-3">
              <input
                className="input"
                placeholder="Short title"
                value={title}
                onChange={(event) => setTitle(event.target.value)}
              />
              <input
                className="input"
                placeholder="Description"
                value={description}
                onChange={(event) => setDescription(event.target.value)}
              />
              <select
                className="input"
                value={priority}
                onChange={(event) => setPriority(event.target.value)}
              >
                <option value="P1">P1 - Critical</option>
                <option value="P2">P2 - High</option>
                <option value="P3">P3 - Medium</option>
              </select>
            </div>
            <button className="btn primary" onClick={createTicket}>
              Create Ticket
            </button>
          </section>

          <section className="card">
            <div className="row between">
              <h2>Ticket Queue</h2>
              <select
                className="input filter"
                value={statusFilter}
                onChange={(event) => setStatusFilter(event.target.value)}
              >
                <option value="">All statuses</option>
                <option value="open">Open</option>
                <option value="in_progress">In progress</option>
                <option value="resolved">Resolved</option>
              </select>
            </div>

            {loading ? <p>Loading tickets...</p> : null}
            {!loading && tickets.length === 0 ? (
              <p>No tickets yet. Create one to get started.</p>
            ) : null}

            <div className="ticket-list">
              {tickets.map((ticket) => (
                <article key={ticket.id} className="ticket-item">
                  <div>
                    <h3>{ticket.title}</h3>
                    <p>{ticket.description || "No description provided"}</p>
                  </div>
                  <div className="ticket-meta">
                    <Badge value={ticket.priority} />
                    <Badge value={ticket.status} />
                    <select
                      className="input"
                      value={ticket.status}
                      onChange={(event) => changeStatus(ticket.id, event.target.value)}
                    >
                      <option value="open">Open</option>
                      <option value="in_progress">In Progress</option>
                      <option value="resolved">Resolved</option>
                    </select>
                  </div>
                </article>
              ))}
            </div>
          </section>
        </>
      )}

      {message ? <p className="message">{message}</p> : null}
    </main>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
