package gigatools.scripts

import com.intellij.openapi.actionSystem.AnAction
import com.intellij.openapi.actionSystem.AnActionEvent
import com.intellij.openapi.command.WriteCommandAction
import com.intellij.openapi.project.Project
import org.jetbrains.annotations.NotNull

import static liveplugin.PluginUtil.registerAction
import static liveplugin.PluginUtil.show

class RegenMegaCategoryLists extends AnAction {
    static String name = "Rebuild Kilo/Giga Category Triggers"

    @Override
    void actionPerformed(@NotNull AnActionEvent event) {
        Project project = event.project
        if (project == null) { return }

        WriteCommandAction.writeCommandAction(project).withName(name).run {
            // test triggers for now
            //buildMegaCategoryList(project, "plugin_test_kilos_trigger", "giga_kilostructures")
            //buildMegaCategoryList(project, "plugin_test_gigas_trigger", "giga_gigastructures")
            show("hello!")
        }

        show("Trigger Rebuild Complete")
    }

    static void register() {
        RegenMegaCategoryLists action = new RegenMegaCategoryLists()
        action.addTextOverride("MainMenu", name)
        registerAction("gigas.regenlists", "", plugindata.actionGroupId, action)
    }
}