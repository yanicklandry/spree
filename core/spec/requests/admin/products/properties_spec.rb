require 'spec_helper'

describe "Properties" do
  stub_authorization!

  before(:each) do
    visit spree.admin_path
    click_link "Products"
  end

  context "listing product properties" do
    it "should list the existing product properties" do
      create(:property, :name => 'shirt size', :presentation => 'size')
      create(:property, :name => 'shirt fit', :presentation => 'fit')

      click_link "Properties"
      find('table#listing_properties tbody tr:nth-child(1) td:nth-child(1)').text.should == "shirt size"
      find('table#listing_properties tbody tr:nth-child(1) td:nth-child(2)').text.should == "size"
      find('table#listing_properties tbody tr:nth-child(2) td:nth-child(1)').text.should == "shirt fit"
      find('table#listing_properties tbody tr:nth-child(2) td:nth-child(2)').text.should == "fit"
    end
  end

  context "creating a property" do
    it "should allow an admin to create a new product property", :js => true do
      click_link "Properties"
      click_link "new_property_link"
      within('#new_property') { page.should have_content("New Property") }

      fill_in "property_name", :with => "color of band"
      fill_in "property_presentation", :with => "color"
      click_button "Create"
      page.should have_content("successfully created!")
    end
  end

  context "editing a property" do
    before(:each) do
      create(:property)
      click_link "Properties"
      within('table#listing_properties tbody tr:nth-child(1)') { click_link "Edit" }
    end

    it "should allow an admin to edit an existing product property" do
      fill_in "property_name", :with => "model 99"
      click_button "Update"
      page.should have_content("successfully updated!")
      page.should have_content("model 99")
    end

    it "should show validation errors" do
      fill_in "property_name", :with => ""
      click_button "Update"
      page.should have_content("Name can't be blank")
    end
  end

  context "linking a property to a product", :js => true do
    before do
      create(:product)
      visit spree.admin_products_path
      click_link "Edit"
      click_link "Product Properties"
    end

    # Regression test for #2279
    specify do 
      fill_in "product_product_properties_attributes_0_property_name", :with => "A Property"
      fill_in "product_product_properties_attributes_0_value", :with => "A Value"
      click_button "Update"
      click_link "Product Properties"

      wait_until do
        page.find("tbody#product_properties", :visible => true)
      end

      all("tbody#product_properties tr").count.should == 2
    end
  end
end
