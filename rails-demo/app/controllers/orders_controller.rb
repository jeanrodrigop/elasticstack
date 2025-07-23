class OrdersController < ApplicationController
  # Probability that a request fails on purpose (0..1).
  ERROR_RATE = ENV.fetch("ERROR_RATE", "0.25").to_f

  # Each lambda raises a different exception so the APM "Errors" view shows a
  # realistic spread of failure types.
  RANDOM_FAILURES = [
    -> { raise StandardError, "inventory service unavailable" },
    -> { raise ArgumentError, "invalid promo code" },
    -> { Integer("not-a-number") }, # raises ArgumentError
    -> { raise PaymentError, "card declined by issuer" },
  ].freeze

  before_action :maybe_fail!, only: %i[index create]

  # GET /orders — read path (SELECT span -> postgresql dependency).
  def index
    orders = Order.order(created_at: :desc).limit(10)
    Rails.logger.info("listed #{orders.size} orders")
    render json: orders
  end

  # GET /orders/:id — random not-found becomes a reported 404.
  def show
    order = Order.find(params[:id])
    render json: order
  rescue ActiveRecord::RecordNotFound => e
    ElasticAPM.report(e, handled: true)
    Rails.logger.warn("order not found id=#{params[:id]}")
    render json: { error: "order not found" }, status: :not_found
  end

  # POST/GET /orders — write path: persists a random order (INSERT span).
  def create
    order = Order.create!(
      item: Order::ITEMS.sample,
      customer: "cust-#{rand(1..500)}",
      amount_cents: rand(100..50_000),
      status: "pending",
    )
    Rails.logger.info("created order ##{order.id} (#{order.item})")
    render json: order, status: :created
  end

  # GET /checkout — multi-step trace: INSERT -> charge (may fail) -> UPDATE.
  # Always writes a row first, so it produces DB dependency data even when the
  # payment step blows up.
  def checkout
    order = Order.create!(
      item: Order::ITEMS.sample,
      customer: "cust-#{rand(1..500)}",
      amount_cents: rand(500..30_000),
      status: "pending",
    )
    charge!(order)
    order.update!(status: "confirmed")
    Rails.logger.info("checkout confirmed order ##{order.id}")
    render json: order
  end

  # GET /boom — always raises, to guarantee a steady error signal.
  def boom
    raise "intentional boom for testing"
  end

  private

  def maybe_fail!
    RANDOM_FAILURES.sample.call if rand < ERROR_RATE
  end

  # Simulate a downstream payment call as a dedicated APM span; fail some of the
  # time (unhandled -> 500, captured by APM).
  def charge!(order)
    ElasticAPM.with_span("payment.charge", "external", subtype: "payment_gateway") do
      sleep(rand(0.02..0.15))
      if rand < ERROR_RATE * 1.5
        order.update!(status: "failed")
        Rails.logger.error("payment failed for order ##{order.id}")
        raise PaymentError, "payment declined for order ##{order.id}"
      end
    end
  end
end
