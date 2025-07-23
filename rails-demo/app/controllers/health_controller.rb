class HealthController < ApplicationController
  # Liveness endpoint used by the container healthcheck — never fails.
  def show
    render json: { status: "ok", service: EcsApmFormatter::SERVICE }
  end
end
