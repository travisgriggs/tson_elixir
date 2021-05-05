defmodule TSON.Duration do
  alias __MODULE__

  defstruct amount: 0, unit: :second

  def reduced(%Duration{amount: amount, unit: :minute}) when amount |> rem(60) == 0 do
    %Duration{amount: amount |> div(60), unit: :hour}
  end

  def reduced(%Duration{amount: amount, unit: :second}) when amount |> rem(60) == 0 do
    reduced(%Duration{amount: amount |> div(60), unit: :minute})
  end

  def reduced(%Duration{amount: amount, unit: :millisecond}) when amount |> rem(1000) == 0 do
    reduced(%Duration{amount: amount |> div(1000), unit: :second})
  end

  def reduced(%Duration{amount: amount, unit: :microsecond}) when amount |> rem(1000) == 0 do
    reduced(%Duration{amount: amount |> div(1000), unit: :millisecond})
  end

  def reduced(%Duration{amount: amount, unit: :nanosecond}) when amount |> rem(1000) == 0 do
    reduced(%Duration{amount: amount |> div(1000), unit: :microsecond})
  end

  def reduced(%Duration{} = duration), do: duration
end
