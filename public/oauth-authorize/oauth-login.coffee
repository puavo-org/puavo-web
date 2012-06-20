

class Login

  # Backbone.js style scoped jQuery
  $: (selector) -> $(selector, @$el)

  constructor: ({el}) ->
    @$el = $ el
    @selection = @$ ".chzn-select"


    if localStorage.lastUsedOrgKey
      @selectOrganisation localStorage.lastUsedOrgKey
      @loginOnly()
    else
      @organisationSelectionOnly()

    @selection.chosen no_results_text: "Organisaatioita ei löydy sanalla: "


    @$("button.next").click (e) =>
      e.preventDefault()
      @selectOrganisation $("select").get(0).value
      @loginOnly()

    @$("a.change-organization").click (e) =>
      e.preventDefault()
      @organisationSelectionOnly()


  selectOrganisation: (orgKey) ->
    @selection.val orgKey
    humanName = @$("option[value=#{ orgKey }]").text()
    @$(".chosen-organization .container").text humanName
    localStorage.lastUsedOrgKey = orgKey


  organisationSelectionOnly: ->
    @$el.addClass "organisation-only"
    @$el.removeClass "login-only"
    @selection.get(0).focus()

  loginOnly: ->
    @$el.addClass "login-only"
    @$el.removeClass "organisation-only"
    @$("#oauth_uid").get(0).focus()



$ ->
  window.login = new Login el: $("body").get 0
