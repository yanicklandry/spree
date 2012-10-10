require 'spec_helper'

module Spree
  describe OrderUpdater do
    let(:order) { stub_model(Spree::Order) }
    let(:updater) { Spree::OrderUpdater.new(order) }

    it "updates totals" do
      payments = [stub(:amount => 5), stub(:amount => 5)]
      order.stub_chain(:payments, :completed).and_return(payments)

      line_items = [stub(:amount => 10), stub(:amount => 20)]
      order.stub :line_items => line_items

      adjustments = [stub(:amount => 10), stub(:amount => -20)]
      order.stub_chain(:adjustments, :eligible).and_return(adjustments)

      updater.update_totals
      order.payment_total.should == 10
      order.item_total.should == 30
      order.adjustment_total.should == -10
      order.total.should == 20
    end

    context "updating shipment state" do
      before do
        order.stub_chain(:shipments, :shipped, :count).and_return(0)
        order.stub_chain(:shipments, :ready, :count).and_return(0)
        order.stub_chain(:shipments, :pending, :count).and_return(0)
      end

      it "is backordered" do
        order.stub :backordered? => true
        updater.update_shipment_state

        order.shipment_state.should == 'backorder'
      end

      it "is nil" do
        order.stub_chain(:shipments, :count).and_return(0)

        updater.update_shipment_state
        order.shipment_state.should be_nil
      end


      [:shipped, :ready, :pending].each do |state|
        it "is #{state}" do
          order.stub_chain(:shipments, :count).and_return(1)
          order.stub_chain(:shipments, state, :count).and_return(1)

          updater.update_shipment_state
          order.shipment_state.should == state.to_s
        end
      end

      it "is partial" do
        order.stub_chain(:shipments, :count).and_return(2)
        order.stub_chain(:shipments, :ready, :count).and_return(1)
        order.stub_chain(:shipments, :pending, :count).and_return(1)

        updater.update_shipment_state
        order.shipment_state.should == 'partial'
      end
    end

    context "updating payment state" do
      it "is failed if last payment failed" do
        order.stub_chain(:payments, :last, :state).and_return('failed')

        updater.update_payment_state
        order.payment_state.should == 'failed'
      end

      it "is balance due with no line items" do
        order.stub_chain(:line_items, :empty?).and_return(true)

        updater.update_payment_state
        order.payment_state.should == 'balance_due'
      end

      it "is credit owed if payment is above total" do
        order.stub_chain(:line_items, :empty?).and_return(false)
        order.stub :payment_total => 31
        order.stub :total => 30

        updater.update_payment_state
        order.payment_state.should == 'credit_owed'
      end

      it "is paid if order is paid in full" do
        order.stub_chain(:line_items, :empty?).and_return(false)
        order.stub :payment_total => 30
        order.stub :total => 30

        updater.update_payment_state
        order.payment_state.should == 'paid'
      end
    end


    it "state change" do
      order.shipment_state = 'shipped'
      state_changes = stub
      order.stub :state_changes => state_changes
      state_changes.should_receive(:create).with({
        :previous_state => nil,
        :next_state => 'shipped',
        :name => 'shipment',
        :user_id => nil
      }, :without_protection => true)

      order.state_changed('shipment')
    end

    it "updates each shipment" do
      shipment = stub_model(Shipment)
      shipments = [shipment]
      order.stub :shipments => shipments
      shipments.stub :ready => []
      shipments.stub :pending => []
      shipments.stub :shipped => []

      shipment.should_receive(:update!).with(order)

      updater.update
    end

    it "updates totals twice" do
      updater.should_receive(:update_totals).twice

      updater.update
    end
  end
end
