$(document).ready(function() {
  function update_wlan_fields_visibility(index, select_wlan_type) {
    var wlan_type = select_wlan_type.val();

    var tr_wlan_ap       = $('tr.wlan_ap_' + index);
    var tr_wlan_certs    = $('tr.wlan_certs_' + index);
    var tr_wlan_identity = $('tr.wlan_identity_' + index);
    var tr_wlan_password = $('tr.wlan_password_' + index);

    var show_wlan_ap       = (wlan_type !== 'eap-tls');
    var show_wlan_certs    = (wlan_type === 'eap-tls');
    var show_wlan_identity = (wlan_type === 'eap-tls');
    var show_wlan_password = (wlan_type === 'psk');

    for (var i = 0; i < tr_wlan_ap.length; i++) {
      tr_wlan_ap[i].style.display = show_wlan_ap ? 'table-row' : 'none';
    }

    for (var i = 0; i < tr_wlan_certs.length; i++) {
      tr_wlan_certs[i].style.display = show_wlan_certs ? 'table-row' : 'none';
    }

    for (var i = 0; i < tr_wlan_identity.length; i++) {
      tr_wlan_identity[i].style.display
        = show_wlan_identity ? 'table-row' : 'none';
    }

    for (var i = 0; i < tr_wlan_password.length; i++) {
      tr_wlan_password[i].style.display
        = show_wlan_password ? 'table-row' : 'none';
    }
  }

  function make_trigger_for_wlan_type_change(index, select_wlan_type) {
    select_wlan_type.change(function() {
      update_wlan_fields_visibility(index, select_wlan_type);
    });
  }

  for (var i = 0; $('tr.wlan_name_' + i).length > 0; i++) {
    var select_wlan_type = $('#wlan_type_' + i);
    make_trigger_for_wlan_type_change(i, select_wlan_type);
    update_wlan_fields_visibility(i, select_wlan_type);
  }
});
