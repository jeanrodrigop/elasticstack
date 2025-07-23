class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.string  :item, null: false
      t.string  :customer
      t.integer :amount_cents, null: false, default: 0
      t.string  :status, null: false, default: "pending"

      t.timestamps
    end
  end
end
