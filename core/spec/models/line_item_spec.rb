require 'spec_helper'

describe Spree::LineItem do
  before(:each) do
    reset_spree_preferences
  end

  let(:variant) { mock_model(Spree::Variant, :count_on_hand => 95, :price => 9.99) }
  let(:line_item) { Spree::LineItem.new(:quantity => 5) }
  let(:order) do
    shipments = mock(:shipments, :reduce => 0)
    mock_model(Spree::Order, :line_items => [line_item],
                             :inventory_units => [],
                             :shipments => shipments,
                             :completed? => true,
                             :update! => true)
  end

  before do
    line_item.stub(:order => order, :variant => variant, :new_record? => false)
    variant.stub(:currency => "USD")
    Spree::Config.set :allow_backorders => true
  end

  context '#save' do
    it 'should update inventory, totals, and tax' do
      Spree::InventoryUnit.stub(:increase)
      line_item.should_receive(:update_inventory)
      # Regression check for #1481
      order.should_receive(:create_tax_charge!)
      order.should_receive(:update!)
      line_item.save
    end

    context 'when order#completed? is true' do
      # We don't care about this method for these tests
      before { line_item.stub(:update_order) }

      context 'and line_item is a new record' do
        before { line_item.stub(:new_record? => true) }

        it 'should increase inventory' do
          Spree::InventoryUnit.stub(:increase)
          Spree::InventoryUnit.should_receive(:increase).with(order, variant, 5)
          # We don't care about this method for this test
          line_item.stub(:update_order)
          line_item.save
        end
      end

      context 'and quantity is increased' do
        before { line_item.stub(:changed_attributes => {'quantity' => 5}, :quantity => 6) }

        it 'should increase inventory' do
          Spree::InventoryUnit.should_not_receive(:decrease)
          Spree::InventoryUnit.should_receive(:increase).with(order, variant, 1)
          line_item.save
        end
      end

      context 'and quantity is decreased' do
        before { line_item.stub(:changed_attributes => {'quantity' => 5}, :quantity => 3) }

        it 'should decrease inventory' do
          Spree::InventoryUnit.should_not_receive(:increase)
          Spree::InventoryUnit.should_receive(:decrease).with(order, variant, 2)
          line_item.save
        end
      end

      context 'and quantity is not changed' do

        it 'should not manager inventory' do
          Spree::InventoryUnit.should_not_receive(:increase)
          Spree::InventoryUnit.should_not_receive(:decrease)
          line_item.save
        end
      end
    end

    context 'when order#completed? is false' do
      before do
        order.stub(:completed? => false)
        # We don't care about this method for this test
        line_item.stub(:update_order)
      end

      it 'should not manage inventory' do
        Spree::InventoryUnit.should_not_receive(:increase)
        Spree::InventoryUnit.should_not_receive(:decrease)
        line_item.save
      end
    end
  end

  context '#destroy' do
    # Regression test for #1481
    it "applies tax adjustments" do
      # We don't care about this method for this test
      line_item.stub(:remove_inventory)
      order.should_receive(:create_tax_charge!)
      line_item.destroy
    end

    context 'when order.completed? is true' do
      it 'should remove inventory' do
        # We don't care about this method for this test
        line_item.stub(:update_order)
        Spree::InventoryUnit.should_receive(:decrease).with(order, variant, 5)
        line_item.destroy
      end
    end

    context 'when order.completed? is false' do
      before { order.stub(:completed? => false) }

      it 'should not remove inventory' do
        Spree::InventoryUnit.should_not_receive(:decrease)
      end
    end

    context 'with inventory units' do
      let(:inventory_unit) { mock_model(Spree::InventoryUnit, :variant_id => variant.id, :shipped? => false) }
      before do
        order.stub(:inventory_units => [inventory_unit])
        line_item.stub(:order => order, :variant_id => variant.id)
      end

      it 'should allow destroy when no units have shipped' do
        # We don't care about this method for this test
        line_item.stub(:update_order)
        line_item.should_receive(:remove_inventory)
        line_item.destroy.should be_true
      end

      it 'should not allow destroy when units have shipped' do
        inventory_unit.stub(:shipped? => true)
        line_item.should_not_receive(:remove_inventory)
        line_item.destroy.should be_false
      end
    end
  end

  context '(in)sufficient_stock?' do
    context 'when backordering is disabled' do
      before { Spree::Config.set :allow_backorders => false }

      it 'should report insufficient stock when variant is out of stock' do
        line_item.stub_chain :variant, :on_hand => 0
        line_item.insufficient_stock?.should be_true
        line_item.sufficient_stock?.should be_false
      end

      it 'should report insufficient stock when variant has less on_hand that line_item quantity' do
        line_item.stub_chain :variant, :on_hand => 3
        line_item.insufficient_stock?.should be_true
        line_item.sufficient_stock?.should be_false
      end

      it 'should report sufficient stock when variant has enough on_hand' do
        line_item.stub_chain :variant, :on_hand => 300
        line_item.insufficient_stock?.should be_false
        line_item.sufficient_stock?.should be_true
      end

      context 'when line item has been saved' do
        before { line_item.stub(:new_record? => false) }

        it 'should report sufficient stock when reducing purchased quantity' do
          line_item.stub(:changed_attributes => {'quantity' => 6}, :quantity => 5)
          line_item.stub_chain :variant, :on_hand => 0
          line_item.insufficient_stock?.should be_false
          line_item.sufficient_stock?.should be_true
        end

        it 'should report sufficient stock when increasing purchased quantity and variant has enough on_hand' do
          line_item.stub(:changed_attributes => {'quantity' => 5}, :quantity => 6)
          line_item.stub_chain :variant, :on_hand => 1
          line_item.insufficient_stock?.should be_false
          line_item.sufficient_stock?.should be_true
        end

        it 'should report insufficient stock when increasing purchased quantity and new units is more than variant on_hand' do
          line_item.stub(:changed_attributes => {'quantity' => 5}, :quantity => 7)
          line_item.stub_chain :variant, :on_hand => 1
          line_item.insufficient_stock?.should be_true
          line_item.sufficient_stock?.should be_false
        end
      end
    end

    context 'when backordering is enabled' do
      before { Spree::Config.set :allow_backorders => true }

      it 'should report sufficient stock regardless of on_hand value' do
        [-99,0,99].each do |i|
          line_item.stub_chain :variant, :on_hand => i
          line_item.insufficient_stock?.should be_false
          line_item.sufficient_stock?.should be_true
        end
      end
    end
  end

  context 'after shipment made' do
    before do
      shipping_method = mock_model(Spree::ShippingMethod, :calculator => mock(:calculator))
      shipment = Spree::Shipment.new :order => order, :shipping_method => shipping_method
      shipment.stub(:state => 'shipped')
      shipped_inventory_units = 5.times.map { Spree::InventoryUnit.new({ :variant => line_item.variant, :state => 'shipped' }, :without_protection => true) }
      unshipped_inventory_units = 2.times.map { Spree::InventoryUnit.new({ :variant => line_item.variant, :state => 'sold' }, :without_protection => true) }
      inventory_units = shipped_inventory_units + unshipped_inventory_units
      order.stub(:shipments => [shipment])
      shipment.stub(:inventory_units => inventory_units)
      inventory_units.stub(:shipped => shipped_inventory_units)
      shipped_inventory_units.stub(:where).with(:variant_id => line_item.variant_id).and_return(shipped_inventory_units)
      # We don't care about this method for these test
      line_item.stub(:update_order)
    end

    it 'should not allow quantity to be adjusted lower than already shipped units' do
      line_item.quantity = 4
      line_item.save.should be_false
      line_item.errors.size.should == 1
    end

    it "should allow quantity to be adjusted higher than already shipped units" do
      line_item.quantity = 6
      line_item.save.should be_true
    end
  end

  context "destroying" do
    # Regression test for #1233
    it "removes related adjustments" do
      line_item = create(:line_item)
      adjustment = line_item.adjustments.create(:amount => 10, :label => "test")
      line_item.destroy
      lambda { adjustment.reload }.should raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe '.currency' do
    it 'returns the globally configured currency' do
      line_item.currency == 'USD'
    end
  end

  describe ".money" do
    before { line_item.price = 3.50 }
    it "returns a Spree::Money representing the total for this line item" do
      line_item.money.to_s.should == "$17.50"
    end
  end

  describe '.single_money' do
    before { line_item.price = 3.50 }
    it "returns a Spree::Money representing the price for one variant" do
      line_item.single_money.to_s.should == "$3.50"
    end
  end
end
