class PuavoRestProxy

  class BadStatus < Exception
    attr_accessor :response
    def initialize(message, res)
      super(message)
      @response = res
    end
  end

  def initialize(domain, username=nil, password=nil)
    @domain = domain
    @username = username
    @password = password
  end

  def request(method, path, options=nil)
    options = (options || {}).dup

    headers = {
      "host" => @domain
    }.merge(options[:headers] || {})

    options[:headers] = headers

    if !Puavo::CONFIG["puavo_rest"] || !Puavo::CONFIG["puavo_rest"]["host"]
      return render :status => 500, :json => {
        "error" => {
          "code" => "ConfigurationError",
          "message" => "puavo-rest host is not configured"
        }
      }
    end

    rest_url = "#{ Puavo::CONFIG["puavo_rest"]["host"] }#{ path }"

    if @username && @password then
      res = HTTP.basic_auth({ :user => @username, :pass => @password }) \
                .send(method, rest_url, options)
    else
      res = HTTP.send(method, rest_url, options)
    end

    if res.code != 200 then
      raise BadStatus.new("Bad http status #{ res.code } #{ method.to_s.upcase } #{ path }", res)
    end

    return res

  end

  [:get, :post, :put].each do |method|
    define_method(method) do |*args|
      request(method, *args)
    end
  end

end
