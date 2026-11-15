defmodule Jarvis.VSM.Cell do
  @moduledoc "The application-defined Jarvis viable-system Cell."

  use Jido.VSM.Cell,
    name: "jarvis_vsm_cell",
    operations: [
      operations: {Jarvis.VSM.Passive, %{role: "s1"}}
    ],
    roles: [
      s2: {Jarvis.VSM.Passive, %{role: "s2"}},
      s3: {Jarvis.VSM.Passive, %{role: "s3"}},
      s3_star: {Jarvis.VSM.Passive, %{role: "s3_star"}},
      s4: {Jarvis.VSM.Intelligence, %{}},
      s5: {Jarvis.VSM.Policy, %{}}
    ],
    ports: [
      {:in, "jarvis.vsm.review.requested", :s4},
      {:out, "jarvis.vsm.review.completed", :s5}
    ],
    connections: [
      {"jarvis.vsm.recommendation", :s4, :s5}
    ]
end
