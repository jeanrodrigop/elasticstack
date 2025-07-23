Rails.application.routes.draw do
  get "/health", to: "health#show"

  get  "/orders",        to: "orders#index"
  post "/orders",        to: "orders#create"
  get  "/orders/random", to: "orders#create"            # GET-friendly for the load generator
  get  "/orders/:id",    to: "orders#show", constraints: { id: /\d+/ }
  get  "/checkout",      to: "orders#checkout"
  get  "/boom",          to: "orders#boom"

  root to: "health#show"
end
