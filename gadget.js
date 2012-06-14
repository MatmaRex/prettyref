// To narzędzie konwertuje przypisy typu <ref> na przypisy typu {{r}}, 
// przenosząc zawartość przypisu na koniec 
// i pozostawiając w tekście głównym tylko odwołanie.
// 
// Wykorzystuje w tym celu skrypt prettyref i interfejs WWW do niego.
// 
// Źródła:    https://github.com/MatmaRex/prettyref
// Interfejs: https://prettyref.heroku.com/
// 
// 
// Użycie: dodaj
//   importScript("Wikipedysta:Matma Rex/prettyref.js")
// do swojego common.js. 
// 
// W pasku narzędzi pojawi się nowy przycisk ze słowem "ref".
// Kliknij, aby dokonała się magia. Zmiany dokonane w tekście strony
// przed kliknięciem przycisku zostaną utracone.
//
// Autor: Matma Rex, CC-BY-SA 3.0.


function prettyref_run()
{
	importScriptURI(
		location.protocol+"//prettyref.heroku.com/" +
		"?title="+encodeURIComponent(wgTitle) +
		"&format=jsonp" +
		"&callback=prettyref_callback" +
		"&rand="+Math.random()
	)
}

function prettyref_callback(json)
{
	if(json.status != 200)
	{
		if(json.error == 'no refs section present?')
			alert("Nie odnaleziono sekcji z przypisami.")
		else
			alert("Błąd ("+json.status+"): "+json.error+". Przypisy na tej stronie są nieprawidłowo sformatowane lub wykorzystują konstrukcje, które jeszcze nie są obsługiwane."+"\n\n\nDodatkowe informacje (debug):\n"+json.backtrace)
	}
	else
	{
		var wpt = document.getElementById('wpTextbox1')
		var wps = document.getElementById('wpSummary')
		
		wpt.value = json.content
		
		wps.value += ", [[Wikipedysta:Matma_Rex/prettyref.js|przeniesienie refów na koniec]]"
		wps.value = wps.value.replace(/(^|\/\*.+?\*\/ ?), /, '$1')
		
		alert("OK. Przed zapisaniem sprawdź wykonane zmiany!")
	}
}

mw.loader.using("ext.gadget.lib-toolbar", function()
{
	toolbarGadget.addButton({
		title: 'Przenieś refy na koniec',
		alt: '{{r',
		icon: '//upload.wikimedia.org/wikipedia/commons/2/2b/Button_ref_inscription.png',
		onclick: function()
		{
			var wpt = document.getElementById('wpTextbox1')
			if($.trim(wpt.value) == $.trim(wpt.defaultValue) || confirm("Zmiany wprowadzone w tekście zostaną utracone. Kontynuować?")) prettyref_run()
		}
	})
})