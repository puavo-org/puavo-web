
module PuavoRest
class ScheduledJobs < LdapSinatra

  # Resource to be called periodically from a cronjob
  post "/v3/scheduled_jobs" do

    started = Time.now

    LdapModel.setup(:credentials => CONFIG["server"]) do
      School.all.each do |s|
        s.cache_feeds()
      end
    end

    flog.info "feed update done", {
      :time => (Time.now - started).to_f
    }

    "ok"

  end

end
end
