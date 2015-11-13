
# Import tool component

To hack on this start puavo-web in development mode `make server` and start JS
server `make js-server`. The component can be found from the users tab.

Translations are generated using [i18n-js](https://github.com/fnando/i18n-js)
from `config/locales/*.yml`. Type `make js-translations` or `make
js-translations-watch` to generate them.  Configuration is in
`config/i18n-js.yml`.


It's written in React and Redux. You must understand basics of both to
understand this part of puavo-web. More info:

- https://facebook.github.io/react/
- https://github.com/rackt/redux
