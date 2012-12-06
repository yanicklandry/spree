require 'spec_helper'

describe Spree::Order do
  let(:order) { Spree::Order.new }
  before do
    # Ensure state machine has been re-defined correctly
    Spree::Order.define_state_machine!
    # We don't care about this validation here
    order.stub(:require_email)
  end

  context "#next!" do
    context "when current state is confirm" do
      before do 
        order.state = "confirm"
        order.run_callbacks(:create)
        order.stub :payment_required? => true
        order.stub_chain(:payments, :exists?).and_return(true)
        order.stub :process_payments!
        order.stub :has_available_shipment
      end

      it "should finalize order when transitioning to complete state" do
        order.should_receive(:finalize!)
        order.next!
      end

       context "when credit card payment fails" do
         before do
           order.stub(:process_payments!).and_raise(Spree::Core::GatewayError)
         end

         context "when not configured to allow failed payments" do
            before do
              Spree::Config.set :allow_checkout_on_gateway_error => false
            end

            it "should not complete the order" do
               order.next
               order.state.should == "confirm"
             end
          end

         context "when configured to allow failed payments" do
           before do
             Spree::Config.set :allow_checkout_on_gateway_error => true
             order.stub :finalize!
           end

           it "should complete the order" do
              order.next!
              order.state.should == "complete"
            end

         end

       end
    end

    context "when current state is address" do
      before do
        order.stub(:has_available_payment)
        order.state = "address"
      end

      it "adjusts tax rates when transitioning to delivery" do
        # Once because the record is being saved
        # Twice because it is transitioning to the delivery state
        Spree::TaxRate.should_receive(:adjust).twice
        order.next!
      end
    end

    context "when current state is delivery" do
      before do
        order.state = "delivery"
        order.stub :total => 10.0
      end

      context "when transitioning to payment state" do
        it "should create a shipment" do
          order.should_receive(:create_shipment!)
          order.next!
          order.state.should == 'payment'
        end
      end
    end

  end

  context "#can_cancel?" do

    %w(pending backorder ready).each do |shipment_state|
      it "should be true if shipment_state is #{shipment_state}" do
        order.stub :completed? => true
        order.shipment_state = shipment_state
        order.can_cancel?.should be_true
      end
    end

    (SHIPMENT_STATES - %w(pending backorder ready)).each do |shipment_state|
      it "should be false if shipment_state is #{shipment_state}" do
        order.stub :completed? => true
        order.shipment_state = shipment_state
        order.can_cancel?.should be_false
      end
    end

  end

  context "#cancel" do
    let!(:variant) { stub_model(Spree::Variant, :on_hand => 0) }
    let!(:inventory_units) { [stub_model(Spree::InventoryUnit, :variant => variant),
                              stub_model(Spree::InventoryUnit, :variant => variant) ]}
    let!(:shipment) do
      shipment = stub_model(Spree::Shipment)
      shipment.stub :inventory_units => inventory_units
      order.stub :shipments => [shipment]
      shipment
    end

    before do
      order.stub :line_items => [stub_model(Spree::LineItem, :variant => variant, :quantity => 2)]
      order.line_items.stub :find_by_variant_id => order.line_items.first

      order.stub :completed? => true
      order.stub :allow_cancel? => true
    end

    it "should send a cancel email" do
      # Stub methods that cause side-effects in this test
      order.stub :has_available_shipment
      order.stub :restock_items!
      mail_message = mock "Mail::Message"
      Spree::OrderMailer.should_receive(:cancel_email).with(order).and_return mail_message
      mail_message.should_receive :deliver
      order.cancel!
    end

    context "restocking inventory" do
      before do
        shipment.stub(:ensure_correct_adjustment)
        shipment.stub(:update_order)
        Spree::OrderMailer.stub(:cancel_email).and_return(mail_message = stub)
        mail_message.stub :deliver

        order.stub :has_available_shipment
      end

      # Regression fix for #729
      specify do
        Spree::InventoryUnit.should_receive(:decrease).with(order, variant, 2).once
        order.cancel!
      end
    end

    context "resets payment state" do
      before do
        # TODO: This is ugly :(
        # Stubs methods that cause unwanted side effects in this test
        Spree::OrderMailer.stub(:cancel_email).and_return(mail_message = stub)
        mail_message.stub :deliver
        order.stub :has_available_shipment
        order.stub :restock_items!
      end

      context "without shipped items" do
        it "should set payment state to 'credit owed'" do
          order.cancel!
          order.payment_state.should == 'credit_owed'
        end
      end

      context "with shipped items" do
        before do
          order.stub :shipment_state => 'partial'
        end

        it "should not alter the payment state" do
          order.cancel!
          order.payment_state.should be_nil
        end
      end
    end
  end


  # Another regression test for #729
  context "#resume" do
    before do
      order.stub :email => "user@spreecommerce.com"
      order.stub :state => "canceled"
      order.stub :allow_resume? => true

      # Stubs method that cause unwanted side effects in this test
      order.stub :has_available_shipment
    end

    context "unstocks inventory" do
      let(:variant) { stub_model(Spree::Variant) }

      before do
        shipment = stub_model(Spree::Shipment)
        line_item = stub_model(Spree::LineItem, :variant => variant, :quantity => 2)
        order.stub :line_items => [line_item]
        order.line_items.stub :find_by_variant_id => line_item

        order.stub :shipments => [shipment]
        shipment.stub :inventory_units => [stub_model(Spree::InventoryUnit, :variant => variant),
                                           stub_model(Spree::InventoryUnit, :variant => variant) ]
      end

      specify do
        Spree::InventoryUnit.should_receive(:increase).with(order, variant, 2).once
        order.resume!
      end
    end

  end
end
