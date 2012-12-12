module Spree
  class Promotion
    module Rules
      class Role < PromotionRule
        def eligible?(order, options = {})
          order.user.spree_roles.include?(Spree::PerlimpinpinController::ROLE_RETAILER)
        end
      end
    end
  end
end
