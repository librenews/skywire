defmodule Skywire.Repo do
  use Ecto.Repo,
    otp_app: :skywire,
    adapter: Ecto.Adapters.Postgres
end
