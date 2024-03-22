const toggle = (selector, visible) => document.querySelectorAll(selector).forEach(e => e.classList.toggle("hidden", !visible));

function update_wlan_fields_visibility(index, wlan_type)
{
    toggle(`tr.wlan_ap_${index}`, ['open', 'psk'].includes(wlan_type));
    toggle(`tr.wlan_certs_${index}`, ['eap-peap', 'eap-tls', 'eap-ttls'].includes(wlan_type));
    toggle(`tr.wlan_identity_${index}`, ['eap-peap', 'eap-tls', 'eap-ttls'].includes(wlan_type));
    toggle(`tr.wlan_password_${index}`, ['eap-peap', 'eap-tls', 'eap-ttls', 'psk'].includes(wlan_type));
    toggle(`tr.wlan_phase2_auth_${index}`, ['eap-peap', 'eap-tls', 'eap-ttls'].includes(wlan_type));
}

document.addEventListener("DOMContentLoaded", () => {
    for (const [index, select] of document.querySelectorAll("div#content select[id^=wlan_type_]").entries()) {
        select.addEventListener("change", e => update_wlan_fields_visibility(index, e.target.value));
        update_wlan_fields_visibility(index, select.value);
    }
});
