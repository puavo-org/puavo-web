module HasPrinterMixin

  def printer_to_dn(printer)
    if printer.class == String
      printer
    else
      printer.dn
    end
  end

  def has_printer?(printer)
    Array(self.puavoPrinterQueue).include?(printer_to_dn(printer))
  end

  def add_printer(printer)
    return if has_printer?(printer)
    self.puavoPrinterQueue = Array(self.puavoPrinterQueue) + [printer_to_dn(printer)]
  end

  def remove_printer(printer)
    self.puavoPrinterQueue = Array(self.puavoPrinterQueue).select do |printer_dn|
      printer_dn != printer_to_dn(printer)
    end
  end

end
