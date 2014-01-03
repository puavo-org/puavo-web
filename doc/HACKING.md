## Using specific organisation connection in Rails Console

In development

    $ bundle exec rails runner script/puavo-web-prompt.rb
    
In production

    # puavo-web-prompt

## Start a Resque worker with verbose (development)

    $ bundle exec rake resque:work QUEUE='*' VERBOSE=true
