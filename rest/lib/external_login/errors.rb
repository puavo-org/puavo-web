# ExternalLoginError means some error occurred on our side
# ExternalLoginAcceessError means there was a problem
#   accessing the external service
# ExternalLoginConfigError means external logins were badly configured
# ExternalLoginDataError means data from external service had some issue
# ExternalLoginNotConfigured means external logins are not configured
#   in whatever particular case
# ExternalLoginUnavailable means an error at external service
# ExternalLoginUserMissing means user could not found at external service
# ExternalLoginWrongCredentials means user or password was invalid

class ExternalLoginError               < StandardError; end
class ExternalLoginAccessError         < ExternalLoginError; end
class ExternalLoginConfigError         < ExternalLoginError; end
class ExternalLoginDataError           < ExternalLoginError; end
class ExternalLoginNotConfigured       < ExternalLoginError; end
class ExternalLoginPasswordChangeError < ExternalLoginError; end
class ExternalLoginUnavailable         < ExternalLoginError; end
class ExternalLoginPuavoUserMissing    < ExternalLoginError; end
class ExternalLoginUserMissing         < ExternalLoginError; end
class ExternalLoginWrongCredentials    < ExternalLoginError; end
