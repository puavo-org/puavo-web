
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
    active_on ListsController
    active_on Users::ImportController
    active_on ImportToolController

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

    child do
      title { 'Import' }
      link { import_tool_path(@school) }
      active_on ImportToolController
      # XXX: Feature switch!
      hide_when { !current_user.organisation_owner? }
    end

    child do
      title { t('link.lists') }
      link { lists_path(@school) }
      active_on ListsController
    end

  end

  # DEVICES
  child do
    title { t('layouts.application.devices') }
    link { "/devices/#{ @school.id }/devices" } # FIXME
    active_on DevicesController
    active_on PrinterPermissionsController

    child do
      title { t('link.devices') }
      link { devices_path(@school) }
      active_on DevicesController
    end

    child do
      title { t('link.printer_permissions') }
      link { printer_permissions_path(@school) }
      active_on PrinterPermissionsController
    end
  end

end



