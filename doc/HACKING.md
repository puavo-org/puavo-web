## Using specific organisation connection in Rails Console

Start console with `bundle exec rails c`

```ruby
Puavo::Console.new("hogwarts", "password", "admin")
```

https://github.com/opinsys/puavo-users/blob/master/lib/puavo/console.rb
