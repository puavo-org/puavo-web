# The remote recovery on the page of a laptop or a boot server, for the
# controllers of those pages.
module RecoveryActions
  private

  # Reads the recovery of the host into @recovery, or the reason it failed
  # into @recovery_error.
  # @param host [Device, Server]
  def find_recovery(host)
    @recovery = recovery_of(host).find
  rescue DeviceRecovery::CallFailed => error
    @recovery_error = recovery_error_message(error)
  end

  # Opens or closes the recovery of the host, then returns to its page.
  # @param host [Device, Server]
  # @param action [Symbol] :open or :close
  # @param notice [String] the text shown when it succeeds
  # @param host_page [String] the path of the page of the host
  def change_recovery(host, action, notice, host_page)
    recovery_of(host).send(action)
    redirect_to host_page, notice: notice
  rescue DeviceRecovery::CallFailed => error
    redirect_to host_page, alert: recovery_error_message(error)
  end

  # @param host [Device, Server]
  # @return [DeviceRecovery] its recovery, as the signed in person
  def recovery_of(host)
    DeviceRecovery.new(host.puavoHostname, @authentication.dn,
                       @authentication.password)
  end

  # @param error [DeviceRecovery::CallFailed]
  # @return [String] the text that tells the person what failed
  def recovery_error_message(error)
    return t('recoveries.errors.no_answer') if error.error_code.nil?

    t("recoveries.errors.#{ error.error_code }",
      default: t('recoveries.errors.other'))
  end
end
