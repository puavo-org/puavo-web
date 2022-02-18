# Common passwords blocklist loading

def load_common_passwords
  begin
    # One word per line
    File.read("#{Rails.root}/config/common_passwords_blocklist.txt").strip.gsub!("\n", "\t")
  rescue
    # If the file cannot be loaded, use a short built-in list. Taken from
    # https://en.wikipedia.org/wiki/List_of_the_most_common_passwords with
    # a few additions.
    %w(
      000000
      111111
      1111111
      123
      123123
      123321
      1234
      12345
      123456
      1234567
      12345678
      123456789
      1234567890
      12345679
      123qwe
      18atcskd2w
      1q2w3e
      1q2w3e4r
      1q2w3e4r5t
      3rjs1la7qe
      555555
      654321
      666666
      7777777
      987654321
      aa12345678
      abc123
      Dragon
      google
      Iloveyou
      Monkey
      mynoob
      password
      password1
      password123
      qwer
      qwerqwer
      qwerty
      qwerty123
      qwertyuiop
      Qwertyuiop
      salasana
      zxcvbnm
    ).join("\t")
  end
end

# Use tabs to separate entries so we can find full words, not substrings
Puavo::COMMON_PASSWORDS = "\t#{load_common_passwords}\t".freeze
