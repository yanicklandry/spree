#encoding: UTF-8
require 'spec_helper'

module Spree
  describe Money do
    before do
      reset_spree_preferences do |config|
        config.currency = "USD"
        config.currency_symbol_position = :before
        config.display_currency = false
      end
    end

    it "formats correctly" do
      money = Spree::Money.new(10)
      money.to_s.should == "$10.00"
    end

    context "with currency" do
      it "passed in option" do
        money = Spree::Money.new(10, :with_currency => true)
        money.to_s.should == "$10.00 USD"
      end

      it "config option" do
        Spree::Config[:display_currency] = true
        money = Spree::Money.new(10)
        money.to_s.should == "$10.00 USD"
      end
    end

    context "hide cents" do
      it "hides cents suffix" do
        Spree::Config[:hide_cents] = true
        money = Spree::Money.new(10)
        money.to_s.should == "$10"
      end

      it "shows cents suffix" do
        Spree::Config[:hide_cents] = false
        money = Spree::Money.new(10)
        money.to_s.should == "$10.00"
      end
    end

    context "currency parameter" do
      context "when currency is specified in Canadian Dollars" do
        it "uses the currency param over the global configuration" do
          money = Spree::Money.new(10, :currency => 'CAD', :with_currency => true)
          money.to_s.should == "$10.00 CAD"
        end
      end

      context "when currency is specified in Japanese Yen" do
        it "uses the currency param over the global configuration" do
          money = Spree::Money.new(100, :currency => 'JPY')
          money.to_s.should == "¥100"
        end
      end
    end

    context "symbol positioning" do
      it "passed in option" do
        money = Spree::Money.new(10, :symbol_position => :after)
        money.to_s.should == "10.00 $"
      end

      it "passed in option string" do
        money = Spree::Money.new(10, :symbol_position => "after")
        money.to_s.should == "10.00 $"
      end

      it "config option" do
        Spree::Config[:currency_symbol_position] = :after
        money = Spree::Money.new(10)
        money.to_s.should == "10.00 $"
      end
    end

    context "JPY" do
      before do
        reset_spree_preferences do |config|
          config.currency = "JPY"
          config.currency_symbol_position = :before
          config.display_currency = false
        end
      end

      it "formats correctly" do
        money = Spree::Money.new(1000)
        money.to_s.should == "¥1,000"
      end
    end
  end
end
