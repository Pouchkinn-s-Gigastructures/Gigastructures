import com.intellij.openapi.actionSystem.*

import liveplugin.ActionGroupIds
import liveplugin.PluginUtil.registerAction

// depends-on-plugin icu.windea.pls


// Using the "show()" function is often the simplest way to see what's going on in the plugin.
// However, for large messages it's better to use STDOUT or Logger which will write to "idea.log".
// You can find "idea.log" location using `Main menu - Help - Show log`
// or by evaluating com.intellij.openapi.application.PathManager.getLogPath().
//println("Hello world on stdout")
//Logger.getInstance("HelloLogger").info("Hello world")

//val selector = selector(project!!, project?.projectFile).definition()
//
//val search = ParadoxDefinitionSearch.search("plugin_test_trigger","scripted_trigger", selector)
//val result = search.find()
//
//val block = ParadoxScriptElementFactory.createBlock(project!!, "{\n\tis_megastructure_type = gateway_0\n}")
//
//WriteCommandAction.writeCommandAction(project!!).withName("Do The Thing").run<Throwable> {
//    result?.block?.replace(block)
//}

//ActionManager.getInstance().

// #####################################################################################################################
// #### PLUGIN SETUP
// #####################################################################################################################

val pluginActionGroupId = "gigas.group"
val pluginActionGroup = DefaultActionGroup("Gigas", true)
pluginActionGroup.addTextOverride("MainMenu", "Gigastructures")
registerAction(pluginActionGroupId, "", ActionGroupIds.Menu.Tools, pluginActionGroup)


object GigaRegenMegaCategoryLists : AnAction() {
    override fun actionPerformed(e: AnActionEvent) {

    }

}
GigaRegenMegaCategoryLists.addTextOverride("MainMenu", "Do The Thing")
registerAction("test", "",pluginActionGroupId, GigaRegenMegaCategoryLists)