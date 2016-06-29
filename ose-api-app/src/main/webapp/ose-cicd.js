$(document).ready(function(){
      
    var name;
    getPods();

    function getPods() {
      $.ajax({
        url: "/rest/api/pods",
        success: function(result) {
          $.each(result, function(i, item) {
            $("div.ose-podName").append(item.metadata.name);
            $("div.ose-podCreateTime").append(item.metadata.creationTimestamp);
            name = item.metadata.name;
          });
        }
      });
    }

    $("#scaleUpBtn").click(function() {
      $.ajax({
        url: "/rest/api/scaleUp",
        success: function(result) {
          alert("Check to see pods scaled up.");
        }
      });
    });

    $("#scaleDownBtn").click(function() {
      $.ajax({
        url: "/rest/api/scaleDown",
        success: function(result) {
          alert("Check to see pods scaled down.");
        }
      });
    });

    $("#deleteBtn").click(function() {
        console.log(name);
      $.ajax({
        url: "/rest/api/pod/name/" + name,
        type: "DELETE",
        success: function(result) {
          alert("Check to see pod(s) deleted.");
        }
      });
    });

    $("#refreshBtn").click(function() {
      $("div.ose-podName").html("");
      $("div.ose-podCreateTime").html("");
      getPods();
    });
    
});