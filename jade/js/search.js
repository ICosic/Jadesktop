$(document).ready(function() {

  $("#clear-search").click(function() {
    $("input#search[type=text], textarea").val("");
    $("#search-msg").remove();
    $(".search-results").children().remove();
    $("input#search").focus();
  });

  $("input#search").on("mouseover", function() {
    $("input#search").focus();

    if (isElementVisible("#go-online")) {
      $("#search").attr("placeholder", "Search The Internet...");
      $("#mini-browser").slideDown("slow");
    } else {
      $.when($(".category-msg, .recent-files-msg, #recent-used-files-msg, #logo").fadeOut()).done(function() {
        $("#search").attr("placeholder", "Search Applications...");
        $("#search").animate({
          width: "50%"
        });
        $(".category-container, #main-dashboard, #recently-used-files").hide();
        $("#search-icon").addClass("animated slideInLeft");
        $(".search-results, #search-icon").show();
        $(".dash-btn").fadeIn();
        grid(".search-results");
      });
    };
  });

  // Init a timeout variable to be used below
  var timeout = null;

  // Listen for key up events
  $("#search").on("keyup", function() {

    // Assign search value to input
    var searchValue = this.value;

    // Clear the timeout if it has already been set.
    // This will prevent the previous task from executing
    // if it has been less than <MILLISECONDS>
    clearTimeout(timeout);

    // Make a new timeout set to go off in 1000ms
    // This depends how fast people type, it should be ok even for slow typers
    timeout = setTimeout(function() {

      if (searchValue.length !== 0) {

        $(".search-results").empty();
        $("#search-msg").remove();

        if (isElementVisible("#go-online")) {
          // internet search
          var url = 'https://duckduckgo.com/?q='
          var query = url + searchValue
          document.getElementById("duckduckgo").contentWindow.location.href = query;
          notifySend("Searching Term -> " + searchValue);
          $("#mini-browser").slideDown("slow");

        } else {
          app_search(searchValue);
        };

        function app_search(searchValue) {

          searchValue = searchValue.toLocaleLowerCase();

          // search title description and keywords
          var searchLocation = ".application-wrapper"

          // if we have only 1 letter search tittle only
          if (searchValue.length == 1) {
            searchLocation = ".application-wrapper h5"
          };

          $(searchLocation).each(function() {

            if ($(this).text().toLocaleLowerCase().indexOf(searchValue) > -1) {

              if (searchValue.length == 1) {

                if ($(this).text().toLocaleLowerCase().charAt(0) == searchValue) {
                  $(this).parent().parent().clone().prependTo(".search-results");
                };
              } else {

                if ($(this).text().toLocaleLowerCase().trim().startsWith(searchValue)) {
                  // More relevant results first
                  $(this).clone().prependTo(".search-results");
                } else {
                  // Less relevant results last
                  $(this).clone().appendTo(".search-results");
                }
              }

              $(".search-results").masonry("reloadItems").masonry("layout");

              var elementsNumber = $(".search-results " + searchLocation).length;

              if (elementsNumber === 1) {
                $("#search-msg").remove();
                $("#search-container").append("<div id='search-msg'>Press ENTER Key To Launch This Application!</div>");

              } else if (elementsNumber > 1) {
                $("#search-msg").remove();
                $("#search-container").append("<div id='search-msg'>You Have " + elementsNumber + " Matches!</div>");
              }

            } else if ($('.search-results').children().length === 0) {
              $("#search-msg").remove();
              $("#search-container").append("<div id='search-msg'>Sorry No Matches Found!</div>");
            }
          });
        }
      }
    }, 1000);
  });

  $("#search").keypress(function(event) {
    var elementsNumber = $(".search-results .application-wrapper").length;
    var key = event.which;

    if (key === 13 && elementsNumber === 1) {

      var text = "Launching " + $(".search-results h5.application-name").text();
      notifySend(text);

      var launch = $(".search-results .application-wrapper .application-box").attr("href");
      window.location.href = launch;
    }
  });
});
