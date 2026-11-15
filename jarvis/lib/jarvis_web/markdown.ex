defmodule JarvisWeb.Markdown do
  @moduledoc "Renders safe chat Markdown with Lumis syntax highlighting."

  @options [
    extension: [
      autolink: true,
      strikethrough: true,
      table: true,
      tasklist: true
    ],
    parse: [smart: true],
    syntax_highlight: [
      engine: :lumis,
      opts: [formatter: {:html_inline, theme: "catppuccin_mocha"}]
    ]
  ]

  @doc "Converts model Markdown to safe HTML."
  def render(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown, @options)
  end

  @doc "Parses provider text chunks into keyed MDEx documents."
  def stream(chunks), do: MDEx.stream(chunks, @options)

  @doc "Renders one document emitted by `stream/1`."
  def render_document(%MDEx.Document{} = document), do: MDEx.to_html!(document)
end
