defmodule TSON.String do
  alias __MODULE__

  defstruct utf8: ""

  def utf8(binary) when is_binary(binary) do
    %String{utf8: binary}
  end

  def utf8(charlist) when is_list(charlist) do
    charlist |> IO.iodata_to_binary() |> utf8
  end
end
