$(document).ready(function(){

  add_address = function(addr){
    var html = "";
    if(addr!=undefined){
      html += addr['firstname'] + " " + addr['lastname'] + ", ";
      html += addr['address1'] + ", " + addr['address2'] + ", ";
      html += addr['city'] + ", ";

      if(addr['state_id']!=null){
        html += addr['state']['name'] + ", ";
      }else{
        html += addr['state_name'] + ", ";
      }

      html += addr['country']['name'];
    }
    return html;
  }

  format_user_autocomplete = function(item){
    var data = item.data
    var html = "<h4>" + data['email'] +"</h4>";
    html += "<span><strong>Billing:</strong> ";
    html += add_address(data['bill_address']);
    html += "</span>";

    html += "<span><strong>Shipping:</strong> ";
    html += add_address(data['ship_address']);
    html += "</span>";

    return html
  }

  prep_user_autocomplete_data = function(data){
    return $.map(eval(data['users']), function(row) {
      return {
          data: row,
          value: row['email'],
          result: row['email']
      }
    });
  }

  if ($("#customer_search").length > 0) {
    $("#customer_search").autocomplete({
      minChars: 5,
      delay: 500,
      source: function(request, response) {
        var params = { q: $('#customer_search').val(),
                       authenticity_token: AUTH_TOKEN }
        $.get(Spree.routes.user_search + '&' + jQuery.param(params), function(data) {
          result = prep_user_autocomplete_data(data)
          response(result);
        });
      },
      focus: function(event, ui) {
        $('#customer_search').val(ui.item.label);
        $(ui).addClass('ac_over');
        return false;
      },
      select: function(event, ui) {
        $('#customer_search').val(ui.item.label);
        _.each(['bill', 'ship'], function(addr_name){
          var addr = ui.item.data[addr_name + '_address'];
          if(addr!=undefined){
            $('#order_' + addr_name + '_address_attributes_firstname').val(addr['firstname']);
            $('#order_' + addr_name + '_address_attributes_lastname').val(addr['lastname']);
            $('#order_' + addr_name + '_address_attributes_company').val(addr['company']);
            $('#order_' + addr_name + '_address_attributes_address1').val(addr['address1']);
            $('#order_' + addr_name + '_address_attributes_address2').val(addr['address2']);
            $('#order_' + addr_name + '_address_attributes_city').val(addr['city']);
            $('#order_' + addr_name + '_address_attributes_zipcode').val(addr['zipcode']);
            $('#order_' + addr_name + '_address_attributes_state_id').val(addr['state_id']);
            $('#order_' + addr_name + '_address_attributes_country_id').val(addr['country_id']);
            $('#order_' + addr_name + '_address_attributes_phone').val(addr['phone']);
          }
        });

        $('#order_email').val(ui.item.data['email']);
        $('#user_id').val(ui.item.data['id']);
        $('#guest_checkout_true').prop("checked", false);
        $('#guest_checkout_false').prop("checked", true);
        $('#guest_checkout_false').prop("disabled", false);
        return true;
      }
    }).data("autocomplete")._renderItem = function(ul, item) {
      $(ul).addClass('ac_results');
      html = format_user_autocomplete(item);
      return $("<li></li>")
              .data("item.autocomplete", item)
              .append("<a class='ui-menu-item'>" + html + "</a>")
              .appendTo(ul);
    }

    $("#customer_search").data("autocomplete")._resizeMenu = function() {
      var ul = this.menu.element;
      ul.outerWidth(this.element.outerWidth());
    }


  }

  var show_billing = function(show) {
    if(show) {
      $('#shipping').show();
      $('#shipping input').prop("disabled", false);
      $('#shipping select').prop("disabled", false);
    } else {
      $('#shipping').hide();
      $('#shipping input').prop("disabled", true);
      $('#shipping select').prop("disabled", true);
    }
  }

  $('input#order_use_billing').click(function() {
    show_billing(!$(this).is(':checked'));
  });

  $('#guest_checkout_true').change(function() {
    $('#customer_search').val("");
    $('#user_id').val("");
    $('#checkout_email').val("");

    var fields = ["firstname", "lastname", "company", "address1", "address2",
              "city", "zipcode", "state_id", "country_id", "phone"]
    $.each(fields, function(i, field) {
      $('#order_bill_address_attributes' + field).val("");
      $('#order_ship_address_attributes' + field).val("");
    })
  });
});


