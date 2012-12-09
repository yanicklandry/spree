module Spree
  class Calculator::CostPrice < Calculator
    def self.description
      I18n.t(:cost_price)
    end

    def compute(object)
      return if object.nil?
      if object.is_a?(Array)
        return if object.empty?
        order = object.first.order
      else
        order = object
      end
      
      if order.user.spree_roles.include?(Spree::PerlimpinpinController::ROLE_RETAILER)

        order.line_items.each do |line|
          line.update_column :price, line.variant.cost_price
        end
      end
      0
    end
  end
end
