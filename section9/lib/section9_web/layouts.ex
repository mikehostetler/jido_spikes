defmodule Section9Web.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Section 9 · Persistent Repair Team</title>
        <script defer phx-track-static type="text/javascript" src="/assets/phoenix.min.js"></script>
        <script defer phx-track-static type="text/javascript" src="/assets/phoenix_live_view.min.js"></script>
        <script>
          window.addEventListener("DOMContentLoaded", () => {
            const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
            const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {params: {_csrf_token: csrfToken}});
            liveSocket.connect(); window.liveSocket = liveSocket;
          });
        </script>
        <style>
          :root { color-scheme: dark; --bg:#0a0d12; --panel:#121822; --line:#273142; --text:#e7eef8; --muted:#91a0b5; --cyan:#63d3ff; --green:#66e3a4; --amber:#ffc76b; --red:#ff7f8e; }
          * { box-sizing:border-box; } body { margin:0; background:radial-gradient(circle at top,#182234 0,#0a0d12 46%); color:var(--text); font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace; }
          main { max-width:1500px; margin:auto; padding:28px; } h1,h2,h3,p { margin-top:0; } h1 { font:700 34px/1.1 system-ui; letter-spacing:-.03em; } h2 { font:650 18px system-ui; }
          .eyebrow { color:var(--cyan); text-transform:uppercase; letter-spacing:.16em; font-size:11px; } .muted { color:var(--muted); }
          .bar,.grid,.roles { display:grid; gap:14px; } .bar { grid-template-columns:2fr repeat(3,1fr); } .grid { grid-template-columns:1.15fr .85fr; margin-top:14px; } .roles { grid-template-columns:repeat(3,1fr); margin-top:14px; }
          .card { background:color-mix(in srgb,var(--panel) 94%,transparent); border:1px solid var(--line); border-radius:12px; padding:16px; box-shadow:0 12px 40px #0005; overflow:hidden; }
          .metric { font-size:22px; font-weight:700; } .status { color:var(--green); } .gen { color:var(--amber); }
          button { background:#1b2635; color:var(--text); border:1px solid #34445a; border-radius:7px; padding:8px 11px; font:inherit; cursor:pointer; } button:hover { border-color:var(--cyan); } button.danger { color:var(--red); }
          .controls { display:flex; flex-wrap:wrap; gap:8px; margin:16px 0; } pre { white-space:pre-wrap; overflow-wrap:anywhere; background:#090c11; border:1px solid #202a38; border-radius:8px; padding:12px; max-height:330px; overflow:auto; font-size:12px; }
          .timeline { max-height:500px; overflow:auto; } .event { border-left:2px solid var(--line); padding:0 0 14px 13px; } .event strong { color:var(--cyan); }
          .stream { color:var(--amber); min-height:58px; } details { margin-top:10px; } summary { color:var(--muted); cursor:pointer; }
          .role-title { display:flex; justify-content:space-between; } .revision { color:var(--cyan); }
          @media (max-width:900px) { .bar,.grid,.roles { grid-template-columns:1fr; } main { padding:16px; } }
        </style>
      </head>
      <body>{@inner_content}</body>
    </html>
    """
  end
end
