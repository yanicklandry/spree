require 'spec_helper'
require 'active_record/fixtures'

describe "Shipping Methods" do
  stub_authorization!

  let!(:address) { create(:address, :state => create(:state)) }
  let!(:zone) { Spree::Zone.find_by_name("GlobalZone") || create(:global_zone) }
  let!(:shipping_method) { create(:shipping_method, :zone => zone) }

  before(:each) do
    # HACK: To work around no email prompting on check out
    Spree::Order.any_instance.stub(:require_email => false)
    create(:payment_method, :environment => 'test')
    @product = create(:product, :name => "Mug")

    visit spree.admin_path
    click_link "Configuration"
  end


  context "show" do
    it "should display exisiting shipping methods" do
      click_link "Shipping Methods"

      within_row(1) do
        column_text(1).should == shipping_method.name 
        column_text(2).should == zone.name
        column_text(3).should == "Flat Rate (per order)"
        column_text(4).should == "Both"
      end
    end
  end

  context "create" do
    it "should be able to create a new shipping method" do
      click_link "Shipping Methods"
      click_link "admin_new_shipping_method_link"
      page.should have_content("New Shipping Method")
      fill_in "shipping_method_name", :with => "bullock cart"
      click_button "Create"
      page.should have_content("successfully created!")
      page.should have_content("Editing Shipping Method")
    end
  end

  # Regression test for #1331
  context "update" do
    it "can change the calculator", :js => true do
      click_link "Shipping Methods"
      within("#listing_shipping_methods") do
        click_icon :edit
      end

      click_button "Update"
      page.should_not have_content("Shipping method is not found")
    end
  end

  context "availability", :js => true do
    before(:each) do
      @shipping_category = create(:shipping_category, :name => "Default")
      click_link "Shipping Methods"
      click_link "admin_new_shipping_method_link"
    end

    context "when rule is no products match" do
      context "when match rules are satisfied" do
        it "shows the right shipping method on checkout" do
          fill_in "shipping_method_name", :with => "Standard"
          select shipping_method.zone.name, :from => "shipping_method_zone_id"
          select @shipping_category.name, :from => "shipping_method_shipping_category_id"
          check "shipping_method_match_none"
          click_button "Create"

          visit spree.root_path
          click_link "Mug"
          click_button "Add To Cart"
          click_button "Checkout"

          str_addr = "bill_address"
          select address.country.name, :from => "order_#{str_addr}_attributes_country_id"
          ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
            fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
          end
          select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
          check "order_use_billing"
          click_button "Save and Continue"
          page.should have_content("Standard")
        end
      end

      context "when match rules aren't satisfied" do
        before { @product.shipping_category = @shipping_category; @product.save }

        it "shows the right shipping method on checkout" do
          fill_in "shipping_method_name", :with => "Standard"
          select shipping_method.zone.name, :from => "shipping_method_zone_id"
          select @shipping_category.name, :from => "shipping_method_shipping_category_id"
          check "shipping_method_match_none"
          click_button "Create"

          visit spree.root_path
          click_link "Mug"
          click_button "Add To Cart"
          click_button "Checkout"

          str_addr = "bill_address"
          select address.country.name, :from => "order_#{str_addr}_attributes_country_id"
          ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
            fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
          end
          select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
          check "order_use_billing"
          click_button "Save and Continue"
          page.should_not have_content("Standard")
        end
      end
    end

    context "when rule is all products match" do
      context "when match rules are satisfied" do
        before { @product.shipping_category = @shipping_category; @product.save }

        it "shows the right shipping method on checkout" do
          fill_in "shipping_method_name", :with => "Standard"
          select shipping_method.zone.name, :from => "shipping_method_zone_id"
          select @shipping_category.name, :from => "shipping_method_shipping_category_id"
          check "shipping_method_match_all"
          click_button "Create"

          visit spree.root_path
          click_link "Mug"
          click_button "Add To Cart"
          click_button "Checkout"

          str_addr = "bill_address"
          select address.country.name, :from => "order_#{str_addr}_attributes_country_id"
          ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
            fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
          end
          select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
          check "order_use_billing"
          click_button "Save and Continue"
          page.should have_content("Standard")
        end
      end

      context "when match rules aren't satisfied" do
        it "shows the right shipping method on checkout" do
          fill_in "shipping_method_name", :with => "Standard"
          select shipping_method.zone.name, :from => "shipping_method_zone_id"
          select @shipping_category.name, :from => "shipping_method_shipping_category_id"
          check "shipping_method_match_all"
          click_button "Create"

          visit spree.root_path
          click_link "Mug"
          click_button "Add To Cart"
          click_button "Checkout"

          str_addr = "bill_address"
          select address.country.name, :from => "order_#{str_addr}_attributes_country_id"
          ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
            fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
          end
          select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
          check "order_use_billing"
          click_button "Save and Continue"
          page.should_not have_content("Standard")
        end
      end
    end

    context "when rule is at least one products match" do
      before(:each) do
        create(:product, :name => "Shirt")
      end

      context "when match rules are satisfied" do
        before { @product.shipping_category = @shipping_category; @product.save }

        it "shows the right shipping method on checkout" do
          fill_in "shipping_method_name", :with => "Standard"
          select zone.name, :from => "shipping_method_zone_id"
          select @shipping_category.name, :from => "shipping_method_shipping_category_id"
          check "shipping_method_match_one"
          click_button "Create"

          visit spree.root_path
          click_link "Mug"
          click_button "Add To Cart"
          click_link "Home"
          click_link "Shirt"
          click_button "Add To Cart"
          click_button "Checkout"

          str_addr = "bill_address"
          select address.country.name, :from => "order_#{str_addr}_attributes_country_id"
          ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
            fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
          end
          select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
          check "order_use_billing"
          click_button "Save and Continue"
          page.should have_content("Standard")
        end
      end

      context "when match rules aren't satisfied" do
        it "shows the right shipping method on checkout" do
          fill_in "shipping_method_name", :with => "Standard"
          select zone.name, :from => "shipping_method_zone_id"
          select @shipping_category.name, :from => "shipping_method_shipping_category_id"
          check "shipping_method_match_one"
          click_button "Create"

          visit spree.root_path
          click_link "Mug"
          click_button "Add To Cart"
          click_link "Home"
          click_link "Shirt"
          click_button "Add To Cart"
          click_button "Checkout"

          str_addr = "bill_address"
          select address.country.name, :from => "order_#{str_addr}_attributes_country_id"
          ['firstname', 'lastname', 'address1', 'city', 'zipcode', 'phone'].each do |field|
            fill_in "order_#{str_addr}_attributes_#{field}", :with => "#{address.send(field)}"
          end
          select "#{address.state.name}", :from => "order_#{str_addr}_attributes_state_id"
          check "order_use_billing"
          click_button "Save and Continue"
          page.should_not have_content("Standard")
        end
      end
    end
  end
end
