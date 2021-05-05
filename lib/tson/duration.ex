defmodule TSON.Duration do
  alias __MODULE__

  defstruct amount: 0, unit: :second

  def reduced(%Duration{amount: amount, unit: :minute}) when rem(amount, 60) == 0 do
    %Duration{amount: div(amount, 60), unit: :hour}
  end

  def reduced(%Duration{amount: amount, unit: :second}) when rem(amount, 60) == 0 do
    reduced(%Duration{amount: div(amount, 60), unit: :minute})
  end

  def reduced(%Duration{amount: amount, unit: :millisecond}) when rem(amount, 1000) == 0 do
    reduced(%Duration{amount: div(amount, 1000), unit: :second})
  end

  def reduced(%Duration{amount: amount, unit: :microsecond}) when rem(amount, 1000) == 0 do
    reduced(%Duration{amount: div(amount, 1000), unit: :millisecond})
  end

  def reduced(%Duration{amount: amount, unit: :nanosecond}) when rem(amount, 1000) == 0 do
    reduced(%Duration{amount: div(amount, 1000), unit: :microsecond})
  end

  def reduced(%Duration{} = duration), do: duration
end
