

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

    @selection.change (e) =>
      @selectOrganisation e.target.value

    @$(".continue-button").click (e) =>
      e.preventDefault()
      @loginOnly()

    @$("a.change-organization").click (e) =>
      e.preventDefault()
      @organisationSelectionOnly()


  selectOrganisation: (orgKey) ->
    @selection.val orgKey
    humanName = @$("option[value=#{ orgKey }]").text()
    @$(".org-container").text humanName
    localStorage.lastUsedOrgKey = orgKey


  organisationSelectionOnly: ->
    @$el.addClass "organisation-only"
    @$el.removeClass "login-only"

  loginOnly: ->
    @$el.addClass "login-only"
    @$el.removeClass "organisation-only"



$ ->
  window.login = new Login el: $("body").get 0



