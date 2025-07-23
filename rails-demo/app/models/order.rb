class Order < ApplicationRecord
  ITEMS = %w[widget gadget gizmo doohickey thingamajig].freeze

  validates :item, presence: true
  validates :amount_cents, numericality: { greater_than_or_equal_to: 0 }
end
