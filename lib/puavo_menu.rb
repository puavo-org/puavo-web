
require_relative "./meta_menu"

class PuavoMenu < MetaMenu

  # SCHOOL
  child do
    title { t('layouts.application.school') }
    link { school_path(@school) }
    active_on SchoolsController
    active_on Schools::ExternalServicesController

    child do
      title { t('schools.menu.dashboard') }
      link { school_path(@school) }
      active_on SchoolsController
      active_on_action "show", "edit"
    end

    child do
      title { t('schools.menu.admins') }
      link { admins_school_path(@school) }
      active_on_action "admins"
      hide_when { not current_user.organisation_owner? }
    end

    child do
      title { t('schools.menu.wlan') }
      link { wlan_school_path(@school) }
      active_on_action "wlan"
      active_on_action "wlan_update"
      hide_when { not current_user.organisation_owner? }
    end

    child do
      title { t('external_services.title') }
      link { schools_external_services_path(@school) }
      active_on Schools::ExternalServicesController
    end
  end

  # USERS
  child do
    title { t('layouts.application.users')  }
    link { users_path(@school) }
    active_on UsersController
    active_on GroupsController
    active_on RolesController
    active_on Users::ImportController

    child do
      title { t('link.users') }
      link { users_path(@school) }
      active_on UsersController
      active_on Users::ImportController
    end

    child do
      title { t('link.groups') }
      link { groups_path(@school) }
      active_on GroupsController
    end

    child do
      title { t('link.roles') }
      link { roles_path(@school) }
      active_on RolesController
    end
  end

  # DEVICES
  child do
    title { t('layouts.application.devices') }
    link { "/devices/#{ @school.id }/devices" } # FIXME
    active_on DevicesController
    active_on Schools::SchoolPrintersController

    child do
      title { t('link.devices') }
      link { devices_path(@school) }
      active_on DevicesController
    end

    child do
      title { "Printer Permissions" }
      link { schools_school_printers_path(@school) }
      active_on Schools::SchoolPrintersController
    end
  end

end



