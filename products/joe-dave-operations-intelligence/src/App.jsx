import React, { useCallback, useEffect, useState } from 'react';

const API_BASE = (import.meta.env.VITE_API_BASE || 'https://joe-dave-operations-api.uchechukwuanuforo.workers.dev').replace(/\/$/, '');

async function request(path, token) {
  const response = await fetch(API_BASE + path, {
    headers: { Accept: 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || payload.message || `Request failed (${response.status})`);
  return payload;
}

const sections = [
  ['overview', 'Overview'], ['customers', 'Customers'], ['invoices', 'Invoices'],
  ['receipts', 'Receipts'], ['purchasing', 'Purchasing'], ['inventory', 'Inventory'],
  ['expenses', 'Expenses'], ['suppliers', 'Suppliers'], ['team', 'Team & access'],
  ['periods', 'Accounting periods']
];

function recordsFrom(payload) {
  if (Array.isArray(payload)) return payload;
  for (const key of ['items', 'data', 'results', 'records']) if (Array.isArray(payload?.[key])) return payload[key];
  return [];
}

export default function App() {
  const [token, setToken] = useState(() => sessionStorage.getItem('jd_access_token') || '');
  const [page, setPage] = useState('overview');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [workspace, setWorkspace] = useState(null);
  const [records, setRecords] = useState([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const load = useCallback(async (nextPage = page, activeToken = token) => {
    if (!activeToken) return;
    setBusy(true); setError(''); setNotice('');
    try {
      const routes = {
        overview: '/saas/status', customers: '/customers', invoices: '/invoices',
        receipts: '/receipts', purchasing: '/purchase-orders', inventory: '/inventory',
        expenses: '/expenses', suppliers: '/suppliers', team: '/team',
        periods: '/accounting-periods'
      };
      const result = await request(routes[nextPage] || routes.overview, activeToken);
      if (nextPage === 'overview') {
        setWorkspace(result);
        setRecords([]);
      } else {
        setRecords(recordsFrom(result));
      }
    } catch (e) {
      setError(e.message);
      setRecords([]);
    } finally { setBusy(false); }
  }, [page, token]);

  useEffect(() => { if (token) load(page, token); }, [token, page, load]);

  async function signIn(e) {
    e.preventDefault(); setBusy(true); setError('');
    try {
      const response = await fetch(API_BASE + '/auth/login', {
        method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify({ email, password })
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || payload.message || 'Sign-in failed');
      const nextToken = payload.token || payload.access_token || payload.session?.token;
      if (!nextToken) throw new Error('The API did not return an access token. Sign-in was not completed.');
      sessionStorage.setItem('jd_access_token', nextToken);
      setToken(nextToken);
    } catch (e) { setError(e.message); }
    finally { setBusy(false); }
  }

  function signOut() {
    sessionStorage.removeItem('jd_access_token');
    setToken(''); setWorkspace(null); setRecords([]); setPage('overview');
  }

  if (!token) return <main className="login-shell">
    <section className="login-card">
      <div className="brand-mark">J<span>&</span>D</div>
      <p className="eyebrow">OPERATIONS INTELLIGENCE</p>
      <h1>Run the business.<br/><em>See what matters.</em></h1>
      <p className="muted">A connected workspace for real business operations. Sign in to access your own records.</p>
      <form onSubmit={signIn}>
        <label>Email address<input type="email" autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)} required /></label>
        <label>Password<input type="password" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} required /></label>
        <button disabled={busy}>{busy ? 'Signing in…' : 'Sign in securely'} <span>→</span></button>
      </form>
      {error && <p className="error" role="alert">{error}</p>}
      <p className="footnote">Your workspace data is loaded from the Operations API. No sample transactions are displayed.</p>
    </section>
    <aside className="login-aside"><div className="orbit orbit-one"/><div className="orbit orbit-two"/><div className="aside-copy"><span className="live-dot"/> BUILT AROUND YOUR OPERATIONS<h2>One connected view.<br/>Decisions with context.</h2><p>Invoices, inventory, purchasing and people—grounded in your saved business records.</p></div></aside>
  </main>;

  const current = sections.find(s=>s[0]===page)?.[1] || 'Overview';
  return <div className="app-shell">
    <aside className="sidebar">
      <div className="brand"><div className="brand-mark small">J<span>&</span>D</div><div><b>Joe&dave</b><small>OPERATIONS INTELLIGENCE</small></div></div>
      <div className="nav-label">WORKSPACE</div>
      <nav>{sections.map(([id, label])=><button key={id} className={page===id?'nav-item active':'nav-item'} onClick={()=>setPage(id)}><span className="nav-glyph">{({overview:'◫',customers:'◎',invoices:'▤',receipts:'↙',purchasing:'⇄',inventory:'▦',expenses:'↗',suppliers:'◇',team:'♙',periods:'◷'})[id]}</span>{label}</button>)}</nav>
      <div className="sidebar-bottom"><span className="live-dot"/> Connected application<br/><small>Live API · No demo records</small><button className="signout" onClick={signOut}>Sign out ↗</button></div>
    </aside>
    <main className="main-area">
      <header className="topbar"><div><span className="crumb">Workspace /</span> {current}</div><div className="top-actions"><span className="status-pill"><i/> Live data</span><button className="refresh" disabled={busy} onClick={()=>load(page,token)}>{busy?'Loading…':'↻ Refresh'}</button></div></header>
      <section className="page-content">
        <p className="eyebrow">JOE&DAVE / BUSINESS SYSTEMS</p>
        <div className="page-heading"><div><h1>{current}</h1><p className="muted">{page==='overview'?'A clear view of your workspace and its connected operations.':`Records retrieved from your workspace for ${current.toLowerCase()}.`}</p></div></div>
        {error && <div className="error-panel"><b>Could not load live data</b><p>{error}</p><button className="refresh" onClick={()=>load(page,token)}>Try again</button></div>}
        {busy && <div className="loading"><span className="spinner"/> Fetching saved workspace data…</div>}
        {!busy && !error && page==='overview' && <div className="overview-grid">
          <article className="welcome-card"><span className="live-dot"/> WORKSPACE STATUS<h2>Operations, connected.</h2><p>Workspace status is retrieved from the live service. Operational figures will only appear when backed by saved records.</p><button className="primary-action" onClick={()=>setPage('invoices')}>Open receivables <span>→</span></button></article>
          <article className="metric-card"><span>Service status</span><strong>{workspace?.billing_enabled===false?'Active · Billing off':workspace?.status || workspace?.state || 'Connected'}</strong><small>Returned by API</small></article>
          <article className="empty-card"><span className="empty-icon">⌁</span><h3>No invented numbers</h3><p>Financial totals and activity will be calculated from persisted records—not sample data.</p></article>
        </div>}
        {!busy && !error && page!=='overview' && <section className="records-panel">
          <div className="panel-head"><div><h2>{current} records</h2><p>{records.length} record{records.length===1?'':'s'} returned by the API</p></div><span className="status-pill"><i/> Persisted data</span></div>
          {records.length===0 ? <div className="empty-state"><div className="empty-icon large">⌁</div><h3>No {current.toLowerCase()} records found</h3><p>This workspace has no records available from this endpoint, or the endpoint returned an unsupported response. Nothing has been fabricated to fill the screen.</p></div> : <div className="table-wrap"><table><thead><tr>{Object.keys(records[0]).filter(k=>!['password_hash','token','secret'].includes(k.toLowerCase())).slice(0,7).map(k=><th key={k}>{k.replaceAll('_',' ')}</th>)}</tr></thead><tbody>{records.map((row,i)=><tr key={row.id||row.uuid||i}>{Object.entries(row).filter(([k])=>!['password_hash','token','secret'].includes(k.toLowerCase())).slice(0,7).map(([k,v])=><td key={k}>{v===null||v===undefined?'—':typeof v==='object'?JSON.stringify(v):String(v)}</td>)}</tr>)}</tbody></table></div>}
        </section>}
        <footer>Joe&dave Operations Intelligence <span>Independent product · Live data only</span></footer>
      </section>
    </main>
  </div>;
}