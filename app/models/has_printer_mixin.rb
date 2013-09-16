module HasPrinterMixin

  def has_printer?(printer)
    Array(self.puavoPrinterQueue).include?(printer.dn)
  end

  def add_printer(printer)
    return if has_printer?(printer)
    self.puavoPrinterQueue = Array(self.puavoPrinterQueue) + [printer.dn]
  end

  def remove_printer(printer)
    self.puavoPrinterQueue = Array(self.puavoPrinterQueue).select do |printer_dn|
      printer_dn != printer.dn
    end
  end

end
