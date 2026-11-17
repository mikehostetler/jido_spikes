import Config

config :req_llm, :lmstudio,
  base_url: System.get_env("LMSTUDIO_BASE_URL", "http://127.0.0.1:1234/v1")

if api_key = System.get_env("OPENAI_API_KEY") do
  config :req_llm, :openai, api_key: api_key
end

if System.get_env("PHX_SERVER") do
  config :section9, Section9Web.Endpoint, server: true
end

config :section9, Section9Web.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4019"))]
