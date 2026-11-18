defmodule Kura.Jido do
  @moduledoc "The supervised Jido instance for Kura."

  use Jido, otp_app: :kura, namespace: "kura"
end
