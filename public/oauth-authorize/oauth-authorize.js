  $(document).ready(function(){
    $('.continue-button').addClass('active').removeClass('disabled');
    $('.chosen-organization').addClass('disabled');
    $('.inputs').addClass('disabled');
    $('.actions').addClass('disabled');


    $(".chzn-select").chosen({no_results_text: "Organisaatioita ei löydy sanalla: "});


    $(".switch-view").each(function(index){
      $(this).click(function(e){
        e.preventDefault();
        var e1 = $(".chosen-organization");
        var e2 = $(".choose-organization");
        var e3 = $(".inputs");
        var e4 = $(".actions");
        var a = [];
        a.push(e1,e2,e3,e4);
        switch_view(a);
        if ($('.chosen-organization span').length<=0) $('.chosen-organization').prepend('<span>Valittu organisaatio: <strong>' +$('option:selected').text()+'</strong></span>');
        else $('.chosen-organization span').remove();
      });
    });
    function switch_view(elements){
      $(elements).each(function(index){
        $(this).hasClass('disabled') ? $(this).removeClass('disabled') : $(this).addClass('disabled');
        $(this).hasClass('active') ? $(this).removeClass('active') : $(this).addClass('active');
      });
    }
  });
