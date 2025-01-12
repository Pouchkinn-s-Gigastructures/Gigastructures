import com.intellij.openapi.actionSystem.*
import com.intellij.openapi.command.WriteCommandAction
import com.intellij.openapi.project.Project
import icu.windea.pls.lang.search.*
import icu.windea.pls.lang.search.selector.*
import icu.windea.pls.script.psi.ParadoxScriptElementFactory

import liveplugin.ActionGroupIds
import liveplugin.PluginUtil.*

// depends-on-plugin icu.windea.pls



// rewrite the body of a specified scripted trigger with a list of megas which have the matching economic category or a child thereof
fun buildMegaCategoryList(project: Project, triggerName: String, categoryName: String) {
    val selector = selector(project, project.projectFile).definition()

    // find the trigger that we're going to rewrite
    val triggerSearch = ParadoxDefinitionSearch.search(triggerName,"scripted_trigger", selector)
    val trigger = triggerSearch.find()
    if (trigger == null) {
        show("Failed to find scripted trigger: $triggerName")
        return
    }

    // find the economic category we're checking against
    val categorySearch = ParadoxDefinitionSearch.search(categoryName,"economic_category", selector)
    val category = categorySearch.find()
    if (category == null) {
        show("Failed to find economic category: $categoryName")
        return
    }

    // get a list of matching megas

    // create a new block with info and content
    val newBlock = ParadoxScriptElementFactory.createBlock(project, "{\n\t# $categoryName\n\n\tis_megastructure_type = gateway_0\n}")

    // finally, swap the trigger's block for the new one
    trigger.block?.replace(newBlock)
}

// #####################################################################################################################
// #### PLUGIN SETUP
// #####################################################################################################################

val pluginActionGroupId = "gigas.group"
val pluginActionGroup = DefaultActionGroup("Gigas", true)
pluginActionGroup.addTextOverride("MainMenu", "Gigastructures")
registerAction(pluginActionGroupId, "", ActionGroupIds.Menu.Tools, pluginActionGroup)

// regenerate lists for what counts as a kilo or giga
val gigaRegenMegaCategoryListsName = "Rebuild Kilo/Giga Category Triggers"
class GigaRegenMegaCategoryLists : AnAction() {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return

        WriteCommandAction.writeCommandAction(project).withName(gigaRegenMegaCategoryListsName).run<Throwable> {
            // test triggers for now
            buildMegaCategoryList(project, "plugin_test_kilos_trigger", "giga_kilostructures")
            buildMegaCategoryList(project, "plugin_test_gigas_trigger", "giga_gigastructures")
        }

        show("Trigger Rebuild Complete")
    }
}
val gigaRegenMegaCategoryLists = GigaRegenMegaCategoryLists()
gigaRegenMegaCategoryLists.addTextOverride("MainMenu", gigaRegenMegaCategoryListsName)
registerAction("gigas.regenlists", "",pluginActionGroupId, gigaRegenMegaCategoryLists)

println("registered")