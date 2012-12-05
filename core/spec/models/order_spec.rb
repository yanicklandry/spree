# encoding: utf-8

require 'spec_helper'

class FakeCalculator < Spree::Calculator
  def compute(computable)
    5
  end
end

describe Spree::Order do
  before(:each) do
    reset_spree_preferences
  end

  let(:user) { stub_model(Spree::LegacyUser, :email => "spree@example.com") }
  let(:order) { stub_model(Spree::Order, :user => user) }

  before do
    Spree::LegacyUser.stub(:current => mock_model(Spree::LegacyUser, :id => 123))
  end

  context "#products" do
    before :each do
      @variant1 = mock_model(Spree::Variant, :product => "product1")
      @variant2 = mock_model(Spree::Variant, :product => "product2")
      @line_items = [mock_model(Spree::LineItem, :variant => @variant1, :variant_id => @variant1.id, :quantity => 1),
                     mock_model(Spree::LineItem, :variant => @variant2, :variant_id => @variant2.id, :quantity => 2)]
      order.stub(:line_items => @line_items)
    end

    it "should return ordered products" do
      order.products.should == ['product1', 'product2']
    end

    it "contains?" do
      order.contains?(@variant1).should be_true
    end

    it "gets the quantity of a given variant" do
      order.quantity_of(@variant1).should == 1

      @variant3 = mock_model(Spree::Variant, :product => "product3")
      order.quantity_of(@variant3).should == 0
    end

    it "can find a line item matching a given variant" do
      order.find_line_item_by_variant(@variant1).should_not be_nil
      order.find_line_item_by_variant(mock_model(Spree::Variant)).should be_nil
    end
  end

  context "#generate_order_number" do
    it "should generate a random string" do
      order.generate_order_number.is_a?(String).should be_true
      (order.generate_order_number.to_s.length > 0).should be_true
    end
  end

  context "#associate_user!" do
    it "should associate a user with this order" do
      order.user = nil
      order.email = nil
      order.associate_user!(user)
      order.user.should == user
      order.email.should == user.email
    end
  end

  context "#create" do
    it "should assign an order number" do
      order = Spree::Order.create
      order.number.should_not be_nil
    end
  end

  context "#finalize!" do
    let(:order) { Spree::Order.create }
    it "should set completed_at" do
      order.should_receive(:touch).with(:completed_at)
      order.finalize!
    end

    it "should sell inventory units" do
      Spree::InventoryUnit.should_receive(:assign_opening_inventory).with(order)
      order.finalize!
    end

    it "should change the shipment state to ready if order is paid" do
      order.stub :shipping_method => mock_model(Spree::ShippingMethod, :create_adjustment => true, :adjustment_label => "Shipping")
      order.create_shipment!
      order.stub(:paid? => true, :complete? => true)
      order.finalize!
      order.reload # reload so we're sure the changes are persisted
      order.shipment.state.should == 'ready'
      order.shipment_state.should == 'ready'
    end

    after { Spree::Config.set :track_inventory_levels => true }
    it "should not sell inventory units if track_inventory_levels is false" do
      Spree::Config.set :track_inventory_levels => false
      Spree::InventoryUnit.should_not_receive(:sell_units)
      order.finalize!
    end

    it "should send an order confirmation email" do
      mail_message = mock "Mail::Message"
      Spree::OrderMailer.should_receive(:confirm_email).with(order).and_return mail_message
      mail_message.should_receive :deliver
      order.finalize!
    end

    it "should continue even if confirmation email delivery fails" do
      Spree::OrderMailer.should_receive(:confirm_email).with(order).and_raise 'send failed!'
      order.finalize!
    end

    it "should freeze all adjustments" do
      # Stub this method as it's called due to a callback
      # and it's irrelevant to this test
      order.stub :has_available_shipment

      Spree::OrderMailer.stub_chain :confirm_email, :deliver
      adjustment1 = mock_model(Spree::Adjustment, :mandatory => true)
      adjustment2 = mock_model(Spree::Adjustment, :mandatory => false)
      order.stub :adjustments => [adjustment1, adjustment2]
      adjustment1.should_receive(:update_column).with("locked", true)
      adjustment2.should_receive(:update_column).with("locked", true)
      order.finalize!
    end

    it "should log state event" do
      order.state_changes.should_receive(:create).exactly(3).times #order, shipment & payment state changes
      order.finalize!
    end
  end

  context "#process_payments!" do
    it "should process the payments" do
      order.stub(:total).and_return(10)
      payment = stub_model(Spree::Payment)
      payments = [payment]
      order.stub(:payments).and_return(payments)
      payments.first.should_receive(:process!)
      order.process_payments!
    end
  end

  context "#outstanding_balance" do
    it "should return positive amount when payment_total is less than total" do
      order.payment_total = 20.20
      order.total = 30.30
      order.outstanding_balance.should == 10.10
    end
    it "should return negative amount when payment_total is greater than total" do
      order.total = 8.20
      order.payment_total = 10.20
      order.outstanding_balance.should be_within(0.001).of(-2.00)
    end

  end

  context "#outstanding_balance?" do
    it "should be true when total greater than payment_total" do
      order.total = 10.10
      order.payment_total = 9.50
      order.outstanding_balance?.should be_true
    end
    it "should be true when total less than payment_total" do
      order.total = 8.25
      order.payment_total = 10.44
      order.outstanding_balance?.should be_true
    end
    it "should be false when total equals payment_total" do
      order.total = 10.10
      order.payment_total = 10.10
      order.outstanding_balance?.should be_false
    end
  end

  context "#complete?" do
    it "should indicate if order is complete" do
      order.completed_at = nil
      order.complete?.should be_false

      order.completed_at = Time.now
      order.completed?.should be_true
    end
  end

  context "#backordered?" do
    it "should indicate whether any units in the order are backordered" do
      order.stub_chain(:inventory_units, :backordered).and_return []
      order.backordered?.should be_false
      order.stub_chain(:inventory_units, :backordered).and_return [mock_model(Spree::InventoryUnit)]
      order.backordered?.should be_true
    end

    it "should always be false when inventory tracking is disabled" do
      Spree::Config.set :track_inventory_levels => false
      order.stub_chain(:inventory_units, :backordered).and_return [mock_model(Spree::InventoryUnit)]
      order.backordered?.should be_false
    end
  end

  context "#payment_method" do
    it "should return payment.payment_method if payment is present" do
      payments = [create(:payment)]
      payments.stub(:completed => payments)
      order.stub(:payments => payments)
      order.payment_method.should == order.payments.first.payment_method
    end

    it "should return the first payment method from available_payment_methods if payment is not present" do
      create(:payment_method, :environment => 'test')
      order.payment_method.should == order.available_payment_methods.first
    end
  end

  context "#allow_checkout?" do
    it "should be true if there are line_items in the order" do
      order.stub_chain(:line_items, :count => 1)
      order.checkout_allowed?.should be_true
    end
    it "should be false if there are no line_items in the order" do
      order.stub_chain(:line_items, :count => 0)
      order.checkout_allowed?.should be_false
    end
  end

  context "#item_count" do
    before do
      @order = create(:order, :user => user)
      @order.line_items = [ create(:line_item, :quantity => 2), create(:line_item, :quantity => 1) ]
    end
    it "should return the correct number of items" do
      @order.item_count.should == 3
    end
  end

  context "#amount" do
    before do
      @order = create(:order, :user => user)
      @order.line_items = [ create(:line_item, :price => 1.0, :quantity => 2), create(:line_item, :price => 1.0, :quantity => 1) ]
    end
    it "should return the correct lum sum of items" do
      @order.amount.should == 3.0
    end
  end

  context "#can_cancel?" do
    it "should be false for completed order in the canceled state" do
      order.state = 'canceled'
      order.shipment_state = 'ready'
      order.completed_at = Time.now
      order.can_cancel?.should be_false
    end

    it "should be true for completed order with no shipment" do
      order.state = 'complete'
      order.shipment_state = nil
      order.completed_at = Time.now
      order.can_cancel?.should be_true
    end
  end

  context "rate_hash" do
    let(:shipping_method_1) { mock_model Spree::ShippingMethod, :name => 'Air Shipping', :id => 1, :calculator => mock('calculator') }
    let(:shipping_method_2) { mock_model Spree::ShippingMethod, :name => 'Ground Shipping', :id => 2, :calculator => mock('calculator') }

    before do
      shipping_method_1.calculator.stub(:compute).and_return(10.0)
      shipping_method_2.calculator.stub(:compute).and_return(0.0)
      order.stub(:available_shipping_methods => [ shipping_method_1, shipping_method_2 ])
    end

    it "should return shipping methods sorted by cost" do
      rate_1, rate_2 = order.rate_hash

      rate_1.shipping_method.should == shipping_method_2
      rate_1.cost.should == 0.0
      rate_1.name.should == "Ground Shipping"
      rate_1.id.should == 2

      rate_2.shipping_method.should == shipping_method_1
      rate_2.cost.should == 10.0
      rate_2.name.should == "Air Shipping"
      rate_2.id.should == 1
    end

    it "should not return shipping methods with nil cost" do
      shipping_method_1.calculator.stub(:compute).and_return(nil)
      order.rate_hash.count.should == 1
      rate_1 = order.rate_hash.first

      rate_1.shipping_method.should == shipping_method_2
      rate_1.cost.should == 0
      rate_1.name.should == "Ground Shipping"
      rate_1.id.should == 2
    end

  end

  context "insufficient_stock_lines" do
    let(:line_item) { mock_model Spree::LineItem, :insufficient_stock? => true }

    before { order.stub(:line_items => [line_item]) }

    it "should return line_item that has insufficent stock on hand" do
      order.insufficient_stock_lines.size.should == 1
      order.insufficient_stock_lines.include?(line_item).should be_true
    end

  end

  context "#add_variant" do
    it "should update order totals" do
      order = Spree::Order.create

      order.item_total.to_f.should == 0.00
      order.total.to_f.should == 0.00

      product = Spree::Product.create!(:name => 'Test', :sku => 'TEST-1', :price => 22.25)
      order.add_variant(product.master)

      order.item_total.to_f.should == 22.25
      order.total.to_f.should == 22.25
    end
  end

  context "empty!" do
    it "should clear out all line items and adjustments" do
      order = stub_model(Spree::Order)
      order.stub(:line_items => line_items = [])
      order.stub(:adjustments => adjustments = [])
      order.line_items.should_receive(:destroy_all)
      order.adjustments.should_receive(:destroy_all)

      order.empty!
    end
  end

  context "#display_outstanding_balance" do
    it "returns the value as a spree money" do
      order.stub(:outstanding_balance) { 10.55 }
      order.display_outstanding_balance.should == Spree::Money.new(10.55)
    end
  end

  context "#display_item_total" do
    it "returns the value as a spree money" do
      order.stub(:item_total) { 10.55 }
      order.display_item_total.should == Spree::Money.new(10.55)
    end
  end

  context "#display_adjustment_total" do
    it "returns the value as a spree money" do
      order.adjustment_total = 10.55
      order.display_adjustment_total.should == Spree::Money.new(10.55)
    end
  end

  context "#display_total" do
    it "returns the value as a spree money" do
      order.total = 10.55
      order.display_total.should == Spree::Money.new(10.55)
    end
  end

  context "#currency" do
    context "when object currency is ABC" do
      before { order.currency = "ABC" }

      it "returns the currency from the object" do
        order.currency.should == "ABC"
      end
    end

    context "when object currency is nil" do
      before { order.currency = nil }

      it "returns the globally configured currency" do
        order.currency.should == "USD"
      end
    end
  end

  # Regression tests for #2179
  context "#merge!" do
    let(:variant) { Factory(:variant) }
    let(:order_1) { Spree::Order.create }
    let(:order_2) { Spree::Order.create }

    it "destroys the other order" do
      order_1.merge!(order_2)
      lambda { order_2.reload }.should raise_error(ActiveRecord::RecordNotFound)
    end

    context "merging together two orders with line items for the same variant" do
      before do
        order_1.add_variant(variant)
        order_2.add_variant(variant)
      end

      specify do
        order_1.merge!(order_2)
        order_1.line_items.count.should == 1

        line_item = order_1.line_items.first
        line_item.quantity.should == 2
        line_item.variant_id.should == variant.id
      end
    end

    context "merging together two orders with different line items" do
      let(:variant_2) { Factory(:variant) }

      before do
        order_1.add_variant(variant)
        order_2.add_variant(variant_2)
      end

      specify do
        order_1.merge!(order_2)
        line_items = order_1.line_items
        line_items.count.should == 2

        # No guarantee on ordering of line items, so we do this:
        line_items.map(&:quantity).should =~ [1,1]
        line_items.map(&:variant_id).should =~ [variant.id, variant_2.id]
      end
    end
  end

  # Regression test for #2191
  context "when an order has an adjustment that zeroes the total, but another adjustment for shipping that raises it above zero" do
    let!(:persisted_order) { create(:order) }
    let!(:line_item) { create(:line_item) }
    let!(:shipping_method) do
      sm = create(:shipping_method)
      sm.calculator.preferred_amount = 10
      sm.save
      sm
    end

    before do
      # Don't care about available payment methods in this test
      persisted_order.stub(:has_available_payment => false)
      persisted_order.line_items << line_item
      persisted_order.adjustments.create(:amount => -line_item.amount, :label => "Promotion")
      persisted_order.state = 'delivery'
      persisted_order.save # To ensure new state_change event
    end

    it "transitions from delivery to payment" do
      persisted_order.shipping_method = shipping_method
      persisted_order.next!
      persisted_order.state.should == "payment"
    end
  end
end
