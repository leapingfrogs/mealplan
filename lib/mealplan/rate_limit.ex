defmodule Mealplan.RateLimit do
  @moduledoc """
  In-memory (ETS) rate limiter. A single node is all we run, so ETS is
  sufficient; limits reset on restart.
  """
  use Hammer, backend: :ets
end
