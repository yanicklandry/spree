require_dependency 'spree/calculator'
# For #to_d method on Ruby 1.8
require 'bigdecimal/util'

module Spree
  class Calculator::PriceSack < Calculator
    def self.description
      I18n.t(:custom_shipping_calculator)
    end

    # as object we always get line items, as calculable we have Coupon, ShippingMethod
    def compute(object=nil)
      item_total = object.line_items.map(&:amount).sum
      if item_total >= 100
        0
      elsif item_total >= 50
        15
      else
        10
      end
    end
  end
end
