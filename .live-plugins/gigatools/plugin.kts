//package gigatools // if this is uncommented the whole thing explodes apparently

import Plugin.GigaYAMLUtil.asText
import Plugin.GigaYAMLUtil.getValueAndCast
import com.intellij.codeInsight.completion.*
import com.intellij.codeInsight.lookup.LookupElementBuilder
import com.intellij.codeInspection.ProblemHighlightType
import com.intellij.lang.LanguageAnnotators
import com.intellij.lang.LanguageExtension
import com.intellij.lang.annotation.AnnotationHolder
import com.intellij.lang.annotation.Annotator
import com.intellij.lang.annotation.HighlightSeverity
import com.intellij.openapi.Disposable
import com.intellij.openapi.actionSystem.*
import com.intellij.openapi.application.ReadAction
import com.intellij.openapi.application.runReadAction
import com.intellij.openapi.command.WriteCommandAction
import com.intellij.openapi.editor.DefaultLanguageHighlighterColors
import com.intellij.openapi.editor.colors.TextAttributesKey.createTextAttributesKey
import com.intellij.openapi.project.Project
import com.intellij.openapi.util.TextRange
import com.intellij.patterns.PlatformPatterns
import com.intellij.psi.PsiComment
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiManager
import com.intellij.psi.PsiWhiteSpace
import com.intellij.psi.search.FilenameIndex
import com.intellij.psi.search.GlobalSearchScope
import com.intellij.psi.search.ProjectScope
import com.intellij.psi.search.PsiSearchHelper
import com.intellij.util.ProcessingContext
import com.intellij.util.concurrency.AppExecutorUtil
import com.intellij.util.io.await
import icu.windea.pls.lang.definitionInfo
import icu.windea.pls.lang.search.*
import icu.windea.pls.lang.search.selector.*
import icu.windea.pls.lang.util.ParadoxLocaleManager
import icu.windea.pls.lang.util.renderer.ParadoxLocalisationTextRenderer
import icu.windea.pls.script.ParadoxScriptLanguage
import icu.windea.pls.script.psi.*
import io.ktor.http.*
import liveplugin.ActionGroupIds
import kotlinx.coroutines.*

import liveplugin.PluginUtil.*
import liveplugin.*
import org.jetbrains.yaml.psi.YAMLFile
import org.jetbrains.yaml.psi.YAMLKeyValue
import org.jetbrains.yaml.psi.YAMLMapping
import org.jetbrains.yaml.psi.YAMLPsiElement
import org.jetbrains.yaml.psi.YAMLScalar

// depends-on-plugin icu.windea.pls
// depends-on-plugin org.jetbrains.plugins.yaml

// #####################################################################################################################
// #### EXTENSIONS AND UTIL
// #####################################################################################################################


object GigaToolsAttributesKeys {
    val PROPERTY_LINE_KEY = createTextAttributesKey("GIGA_TOOLS.PROPERTY_LINE", DefaultLanguageHighlighterColors.STRING)
    val PROPERTY_KEY = createTextAttributesKey("GIGA_TOOLS.PROPERTY", DefaultLanguageHighlighterColors.FUNCTION_DECLARATION)
    val PROPERTY_NAME_KEY = createTextAttributesKey("GIGA_TOOLS.PROPERTY_NAME", DefaultLanguageHighlighterColors.CLASS_NAME)
}



abstract class GigaListConditions {
    companion object {

        // does this definition have EVERY listed tag
        fun hasDefinitionTags(element : ParadoxScriptDefinitionElement, vararg tagsToCheck : String) : Boolean {
            val tags = DefinitionTag.getTagNames(element)
            return tags?.containsAll(tagsToCheck.toList()) ?: false
        }

        // does this definition have ANY listed tag
        fun hasAnyDefinitionTags(element : ParadoxScriptDefinitionElement, vararg tagsToCheck : String) : Boolean {
            val tags = DefinitionTag.getTagNames(element) ?: return false
            for(tag in tags) {
                if (tagsToCheck.contains(tag)) {
                    return true
                }
            }
            return false
        }

        // cache variables for hasEcoCategory
        var cachedEcoCategory : ParadoxScriptDefinitionElement? = null
        var ecoCategoryCheckCache : MutableMap<ParadoxScriptDefinitionElement, Boolean>? = null
        // check if a definition has an eco category or one of its children
        fun hasEcoCategory(element : ParadoxScriptDefinitionElement, categoryToCheck : ParadoxScriptDefinitionElement) : Boolean {
            val resources = element.findProperty("resources", inline = true)
            if (resources == null) {
                //builder.appendLine("# ${mega.name}: no resource block")
                return false
            }

            val elementCategoryName = resources.findProperty("category", inline = true)?.value
            if (elementCategoryName == null) {
                //builder.appendLine("# ${mega.name}: no category given")
                return false
            }
            val category = ParadoxDefinitionSearch.search(elementCategoryName, "economic_category", selector(element.project, element.project.projectFile).definition().distinctByName()).find()
            if (category == null) {
                //builder.appendLine("# ${mega.name}: category has no value")
                return false
            }

            if (cachedEcoCategory != categoryToCheck) {
                cachedEcoCategory = categoryToCheck
                ecoCategoryCheckCache = HashMap()
            }

            val matches = checkEcoCategoryWithLineage(category, categoryToCheck, ecoCategoryCheckCache!!)

            return matches
        }
        fun hasEcoCategoryByName(element : ParadoxScriptDefinitionElement, categoryToCheck: String) : Boolean {
            val wantedCategory = ParadoxDefinitionSearch.search(categoryToCheck,"economic_category", selector(element.project, element.project.projectFile).definition().distinctByName()).find()
            if (wantedCategory == null) {
                //show("Failed to find economic category: $categoryName")
                return false
            }
            return hasEcoCategory(element, wantedCategory)
        }

        // checks if a given economic category is the same as, or a descendant of, another
        fun checkEcoCategoryWithLineage(categoryToCheck: ParadoxScriptDefinitionElement, categoryToMatch: ParadoxScriptDefinitionElement, map: MutableMap<ParadoxScriptDefinitionElement, Boolean>) : Boolean {
            if (map.containsKey(categoryToCheck)) {
                return map[categoryToCheck]!!
            }

            if (categoryToCheck == categoryToMatch) {
                map[categoryToCheck] = true
                return true
            }

            val parent = categoryToCheck.findProperty("parent")
            if (parent == null || parent.value == null) {
                map[categoryToCheck] = false
                return false
            }

            val selector = selector(categoryToCheck.project, categoryToCheck.context).definition().distinctByName()
            val parentCategory = ParadoxDefinitionSearch.search(parent.value!!,"economic_category", selector).find()

            if (parentCategory != null) { return checkEcoCategoryWithLineage(parentCategory, categoryToMatch, map) }

            return false
        }
    }
}



object GigaPsiUtils {

    fun nextNonWhiteSpaceSibling(element: PsiElement): PsiElement? {
        var nextElement: PsiElement? = element.nextSibling ?: element.parent.nextSibling

        while (nextElement != null) {
            if (nextElement is ParadoxScriptRootBlock) {
                nextElement = nextElement.firstChild
            } else if (nextElement !is PsiWhiteSpace) {
                return nextElement
            } else {
                nextElement = nextElement.nextSibling
            }
        }
        return null
    }

    fun prevNonWhiteSpaceSibling(element: PsiElement): PsiElement? {
        var prevElement: PsiElement? = element.prevSibling ?: element.parent.prevSibling

        while (prevElement != null) {
            if (prevElement !is PsiWhiteSpace) {
                return prevElement
            } else {
                prevElement = prevElement.prevSibling
            }
        }
        return null
    }

    fun getElementName(element: ParadoxScriptDefinitionElement) : String {
        val locale = ParadoxLocaleManager.getLocaleConfig("en") // english for standardisation
        val selector = selector(element.project, element).localisation().contextSensitive().preferLocale(locale)
        val loc = ParadoxLocalisationSearch.search(element.name, selector).find() ?: return element.name
        val rendered = ParadoxLocalisationTextRenderer.render(loc).replace("\u200B", "")
        return rendered.ifEmpty { loc.value ?: element.name }
    }

    fun findCommentsWithPrefix(project: Project, prefix: String) : List<PsiComment> {
        // get all comments containing the prefix (slow, so read action)
        val rawResults = runReadAction {
            PsiSearchHelper.getInstance(project).findCommentsContainingIdentifier(prefix, ProjectScope.getProjectScope(project))
        }
        // check that they actually start with it, and cast
        return rawResults.map { e -> if(e !is PsiComment) { error("Not a comment?!") }; e }.filter { e -> e.text.startsWith(prefix) }
    }
}

object ToolData {
    suspend fun loadDataFile(project: Project) {
        val file = ReadAction.nonBlocking<YAMLFile> {
            val files = FilenameIndex.getVirtualFilesByName("gigatools_data.yml", GlobalSearchScope.projectScope(project))
            if (files.isEmpty()) {
                error("Data file not found")
            }
            val psiFile = PsiManager.getInstance(project).findFile(files.first())
            if (psiFile !is YAMLFile) {
                error("Data file isn't YAML")
            }
            psiFile
        }.submit(AppExecutorUtil.getAppExecutorService()).await()

        val rootElement = file.documents.first().topLevelValue
        if (rootElement !is YAMLMapping) { error("Malformed data file, should be a map at root") }
        val root : YAMLMapping = rootElement

        // oh boy this is a complex line
        // for each pair in the tags element's key-value pairs, make a map of the key text and a map of the value's key-value pairs, mapped to THEIR name and a tag entry derived from the value
        definitionTags = root.getValueAndCast<YAMLMapping>("tags").keyValues.associate { categoryPair -> categoryPair.keyText to categoryPair.getValueAndCast<YAMLMapping>().keyValues.associate { entryPair -> entryPair.keyText to DefinitionTag.fromYAMLKeyValue(entryPair) } }

        // get all the list formats too!
        listFormats = root.getValueAndCast<YAMLMapping>("list_formats").keyValues.associate { pair -> pair.keyText to ListFormat.fromYAMLKeyValue(pair) }

    }

    val textGeneratedBlock = "WARNING: The contents of this block are generated by script, any manual changes will be overwritten"

    lateinit var definitionTags: Map<String,Map<String,DefinitionTag>>
    lateinit var listFormats: Map<String, ListFormat>
}

object GigaYAMLUtil {
    inline fun <reified T> YAMLKeyValue.getValueAndCast() : T {
        if (value !is T) { error("Type Mismatch: value of $key is not a ${T::class}: $value (${value?.javaClass})") }
        return value as T
    }

    inline fun <reified T> YAMLMapping.getValueAndCast(key: String) : T {
        val pair = this.getKeyValueByKey(key)
        val value = pair?.value
        if (value !is T) { error("Type Mismatch: value of $key is not a ${T::class}: $value (${value?.javaClass})") }
        return value
    }

    fun YAMLPsiElement.asText() : String {
        //println("asText: $this, ${this.javaClass}")
        if (this is YAMLKeyValue) { return this.value?.asText() ?: error("Pair has no value") }
        if (this is YAMLScalar) { return this.textValue }
        return this.name ?: error("Bad conversion to string")
    }
}

// #####################################################################################################################
// #### TAG DATA
// #####################################################################################################################

class DefinitionTag(val name: String, val shortDesc: String, val fullDesc: String) {

    fun entry(): Pair<String, DefinitionTag> {
        return Pair(name, this)
    }

    override fun toString(): String {
        return "DefinitionTag( \"${name.escapeIfNeeded()}\" | \"${shortDesc.escapeIfNeeded()}\" | \"${fullDesc.escapeIfNeeded()}\" )"
    }

    companion object {
        const val PREFIX = "## Tags:"
        val pattern by lazy { Regex("(?<=\\s)\\@([^\\s]+)") }

        fun fromYAMLKeyValue(tagPair: YAMLKeyValue) : DefinitionTag {
            val name = tagPair.keyText
            val def: YAMLMapping = tagPair.getValueAndCast()
            val desc: String = def.getKeyValueByKey("desc")?.asText() ?: ""
            val fullDesc: String = def.getKeyValueByKey("fullDesc")?.asText() ?: ""

            return DefinitionTag(name, desc, fullDesc)
        }

        fun getTags(definition: ParadoxScriptDefinitionElement) : Set<DefinitionTag>? {
            // get the previous comment
            val prevElement = GigaPsiUtils.prevNonWhiteSpaceSibling(definition)
            if (prevElement !is PsiComment) { return null }

            // check that it starts with the prefix
            val text = prevElement.text
            if (!text.startsWith(PREFIX)) { return null }

            // find valid tags
            val elementType = definition.definitionInfo?.typeConfig?.name ?: "unknown"
            val validTags = ToolData.definitionTags[elementType] ?: return null

            // array for found tags
            val tags : MutableSet<DefinitionTag> = mutableSetOf()

            // check each match against the tags
            val propertyMatches = pattern.findAll(text, PREFIX.length)
            for(match in propertyMatches) {
                // won't be null, or it wouldn't match the pattern
                val tag = match.groups[1]!!.value

                // insert valid tags
                if (validTags.containsKey(tag)) {
                    tags.add(validTags[tag]!!)
                }
            }
            return tags
        }
        fun getTagNames(definition: ParadoxScriptDefinitionElement) : Set<String>? { return getTags(definition)?.map { tag -> tag.name }?.toSet() }
    }
}

class ListFormat(val name: String, val entry: String, val prefix: String?, val suffix: String?) {

    override fun toString(): String {
        return "ListFormat( \"${name.escapeIfNeeded()}\" | \"${entry.escapeIfNeeded()}\" | \"${prefix?.escapeIfNeeded()}\" | \"${suffix?.escapeIfNeeded()}\" )"
    }

    companion object {
        fun fromYAMLKeyValue(tagPair: YAMLKeyValue) : ListFormat {
            val name = tagPair.keyText
            val def: YAMLMapping = tagPair.getValueAndCast()

            val entry: String = def.getKeyValueByKey("entry")?.asText() ?: error("ListFormat $name missing entry field")
            val prefix: String? = def.getKeyValueByKey("prefix")?.asText()
            val suffix: String? = def.getKeyValueByKey("suffix")?.asText()

            return ListFormat(name, entry, prefix, suffix)
        }
    }
}

// #####################################################################################################################
// #### WRAPPER CLASSES
// #####################################################################################################################

open class TaggedDefinition(val def: ParadoxScriptDefinitionElement) {
    val tags: Map<String,DefinitionTag> by lazy { DefinitionTag.getTags(def)?.associate { tag -> tag.name to tag } ?: mapOf() }

    // does this definition have EVERY listed tag
    fun hasTags(vararg tagsToCheck : String) : Boolean {
        return tags.keys.containsAll(tagsToCheck.toList())
    }

    // does this definition have ANY listed tag
    fun hasAnyTags(vararg tagsToCheck : String) : Boolean {
        for(tag in tags.keys) {
            if (tagsToCheck.contains(tag)) {
                return true
            }
        }
        return false
    }

    override fun toString(): String {
        return "(${this.javaClass.canonicalName}: ${def.name})"
    }

    companion object {
        fun resolve(project: Project, type: String, id: String) : TaggedDefinition? {
            val found = ParadoxDefinitionSearch.search(id,type, selector(project, project.projectFile).definition().distinctByName()).find() ?: return null
            return TaggedDefinition(found)
        }
    }
}

class Megastructure(def: ParadoxScriptDefinitionElement) : TaggedDefinition(def) {
    val upgradeFrom : Set<Megastructure> by lazy {
        val upgradeElement = def.findProperty("upgrade_from", inline = true) ?: return@lazy setOf()
        val upgradeBlock = upgradeElement.propertyValue
        if (upgradeBlock !is ParadoxScriptBlockElement) { return@lazy setOf() }

        upgradeBlock.valueList.mapNotNull { v -> println("in ${def.name}: $v, ${v.javaClass}"); resolve(def.project, v.value) }.toSet()
    }

    val upgradeTo : Set<Megastructure> by lazy {
        resolveAll(def.project)
        cache.values.filterNotNull().filter { e -> (e != this) && e.upgradeFrom.contains(this) }.toSet()
    }

    companion object {
        private var resolvedAll = false
        val cache : MutableMap<String,Megastructure?> = mutableMapOf()

        fun resolve(project: Project, id: String) : Megastructure? {
            if (cache.containsKey(id)) { return cache[id] }
            val found = ParadoxDefinitionSearch.search(id, "megastructure", selector(project, project.projectFile).definition().distinctByName()).find()
            val mega = if (found != null) Megastructure(found) else null
            cache[id] = mega
            return mega
        }

        fun resolveAll(project: Project) {
            if (resolvedAll) { return }
            resolvedAll = true
            val found = ParadoxDefinitionSearch.search("megastructure", selector(project, project.projectFile).definition().distinctByName()).findAll()
            cache.putAll(found.filter { e -> !cache.keys.contains(e.name) }.associate { e -> e.name to Megastructure(e) })
        }
    }
}

// #####################################################################################################################
// #### PLUGIN FUNCTION
// #####################################################################################################################

object ListBuilders {
    // rewrite the body of a specified scripted trigger with a list of megas which have the matching economic category or a child thereof
    fun buildMegaCategoryList( project: Project, triggerName: String, predicate: (ParadoxScriptDefinitionElement) -> Boolean ) {
        // find the trigger that we're going to rewrite
        val trigger = ParadoxDefinitionSearch.search(triggerName,"scripted_trigger", selector(project, project.projectFile).definition().distinctByName()).find()
        if (trigger == null) {
            show("Failed to find scripted trigger: $triggerName")
            return
        }

        // get a list of matching megas
        val megas: Iterable<ParadoxScriptDefinitionElement> = ParadoxDefinitionSearch.search("megastructure", selector(project, project.projectFile).definition().distinctByName().filterBy(predicate)).findAll().sortedBy { mega -> mega.name }

        val content = buildListTextWithFormat(megas, ToolData.listFormats["scripted_trigger"]!!, mapOf("trigger" to "\$CONDITION\$"))

        replaceBlockContents(project, trigger.block!!, content)
    }

    fun replaceBlockContents(project: Project, block: ParadoxScriptBlockElement, contents: String) {
        val newBlock = ParadoxScriptElementFactory.createBlock(project, "{\n# ${ToolData.textGeneratedBlock}\n$contents\n}")
        block.replace(newBlock)
    }

    fun buildListTextWithFormat(items: Iterable<ParadoxScriptDefinitionElement>, format: ListFormat, parameters: Map<String,String> = mapOf()) : String {
        val builder = StringBuilder()

        if (format.prefix != null) {
            builder.appendLine(if(parameters.isEmpty()) { format.prefix } else { parameterPattern.replace(format.prefix) { match -> parameters[match.groups[1]!!.value] ?: ""} })
        }

        for(item in items) {
            builder.appendLine(listEntryWithFormat(item, format, parameters))
        }

        if (format.suffix != null) {
            builder.appendLine(if(parameters.isEmpty()) { format.suffix } else { parameterPattern.replace(format.suffix) { match -> parameters[match.groups[1]!!.value] ?: ""} })
        }
        return builder.toString()
    }

    private val namePattern = Regex("£name")
    private val locNamePattern = Regex("£locName")
    private val parameterPattern = Regex("\\$(\\w+)")
    fun listEntryWithFormat(item: ParadoxScriptDefinitionElement, format: ListFormat, parameters: Map<String,String>) : String {
        var string = format.entry

        string = namePattern.replace(string, item.name)

        val locName = lazy { GigaPsiUtils.getElementName(item) }
        string = locNamePattern.replace(string) { _ -> locName.value }

        if (parameters.isNotEmpty()) {
            string = parameterPattern.replace(string) { match -> parameters[match.groups[1]!!.value] ?: ""}
        }

        return string
    }
}

// #####################################################################################################################
// #### PLUGIN SETUP
// #####################################################################################################################



// regenerate lists for what counts as a kilo or giga

class GigaRegenMegaCategoryLists : AnAction() {
    override fun actionPerformed(e: AnActionEvent) {
        val project = e.project ?: return

        //val results = GigaPsiUtils.findCommentsWithPrefix(project, PREFIX)
        //println(results)

        println("dyson_sphere_1")
        val test = Megastructure.resolve(project, "dyson_sphere_1")!!
        println("upgrades from: ${test.upgradeFrom}")
        println("upgrades to: ${test.upgradeTo}")

        println("dyson_sphere_2")
        val test2 = Megastructure.resolve(project, "dyson_sphere_2")!!
        println("upgrades from: ${test2.upgradeFrom}")
        println("upgrades to: ${test2.upgradeTo}")

        //println(Megastructure.cache.values)
        println("MEGA CACHE:")
        for (mega in Megastructure.cache.values) {
            println(mega)
        }
        println("END MEGA CACHE")

        WriteCommandAction.writeCommandAction(project).withName(name).run<Throwable> {

//            for (result in results) {
//                val nextElement: PsiElement = GigaPsiUtils.nextNonWhiteSpaceSibling(result) ?: continue
//                if (nextElement !is ParadoxScriptDefinitionElement) { continue }
//                if (nextElement.block == null) { continue }
//
//                ListBuilders.replaceBlockContents(project, nextElement.block!!, "\n# hello this is a test")
//            }

            val trigger = TaggedDefinition.resolve(project, "scripted_trigger", "another_test_trigger")

            val builder = StringBuilder()
            Megastructure.resolveAll(project)
            val firstStages = Megastructure.cache.values.filterNotNull().filter { e ->
                //e.upgradeFrom.isEmpty() &&
                //e.upgradeTo.isNotEmpty() &&
                //!e.hasAnyTags("technical", "ruined")
                true
            }

            for(mega in firstStages) {
                builder.appendLine("# ${GigaPsiUtils.getElementName(mega.def)}")
                builder.appendLine("or = {")
                builder.appendLine("is_megastructure_type = ${mega.def.name} # ${GigaPsiUtils.getElementName(mega.def)}")
                builder.appendLine("# Tags: ${mega.tags.keys}")
                builder.appendLine("# Upgrades from: ${mega.upgradeFrom.size}")
                builder.appendLine("# Upgrades to: ${mega.upgradeTo.size}")
                builder.appendLine("}")
                builder.appendLine()
            }

            ListBuilders.replaceBlockContents(project, trigger!!.def.block!!, builder.toString())

            // test triggers for now
            ListBuilders.buildMegaCategoryList(project, "plugin_test_kilos_trigger") { def ->
                GigaListConditions.hasEcoCategoryByName(def, "giga_kilostructures")
                        || GigaListConditions.hasDefinitionTags(def, "force_kilo")
            }
            ListBuilders.buildMegaCategoryList(project, "plugin_test_gigas_trigger") { def ->
                GigaListConditions.hasEcoCategoryByName(def, "giga_gigastructures")
                        || GigaListConditions.hasDefinitionTags(def, "force_giga")
            }

            ListBuilders.buildMegaCategoryList(project, "plugin_test_ruined_trigger") { def -> GigaListConditions.hasDefinitionTags(def,"ruined") }
            ListBuilders.buildMegaCategoryList(project, "plugin_test_restored_trigger") { def -> GigaListConditions.hasDefinitionTags(def,"restored") }
            ListBuilders.buildMegaCategoryList(project, "plugin_test_technical_trigger") { def -> GigaListConditions.hasDefinitionTags(def,"technical") }
            ListBuilders.buildMegaCategoryList(project, "plugin_test_megaproject_trigger") { def -> GigaListConditions.hasDefinitionTags(def,"megaproject") }
        }

        show("Trigger Rebuild Complete")
    }

    companion object {
        const val PREFIX = "## Auto List"

        const val name = "Rebuild Kilo/Giga Category Triggers"

        fun register(group: String) {
            val instance = GigaRegenMegaCategoryLists()
            instance.addTextOverride("MainMenu", name)
            registerAction("gigas.regenlists", "", group, instance)
        }
    }
}

object DefinitionPropertyAnnotator : Annotator {
    override fun annotate(element: PsiElement, holder: AnnotationHolder) {
        //println(element.text)
        // only comments
        if (element !is PsiComment) { return }
        // only top level elements
        if (element.parent !is ParadoxScriptRootBlock && element.parent !is ParadoxScriptFile) { return }

        val text = element.text
        // only specially annotated lines
        if (!text.startsWith(DefinitionTag.PREFIX)) { return }
        println("STARTED")

        // get next non-whitespace element or bail
        val nextElement: PsiElement = GigaPsiUtils.nextNonWhiteSpaceSibling(element) ?: return
        // only definition lines
        if (nextElement !is ParadoxScriptDefinitionElement) { return }
        // work out what type of thing we're looking at for getting valid tags
        val elementType = nextElement.definitionInfo?.typeConfig?.name ?: "unknown"
        // get the valid tags or abort if there aren't any
        val validTags = ToolData.definitionTags[elementType] ?: return

        // mark the prefix
        val prefixRange = TextRange.from(element.textRange.startOffset, DefinitionTag.PREFIX.length)
        holder.newSilentAnnotation(HighlightSeverity.INFORMATION).range(prefixRange).textAttributes(GigaToolsAttributesKeys.PROPERTY_LINE_KEY).create()

        // find all properties via pattern
        val propertyMatches = DefinitionTag.pattern.findAll(text, DefinitionTag.PREFIX.length)
        for(match in propertyMatches) {
            // the @ at the start
            val markerRange = TextRange.from(element.textRange.startOffset + match.range.first, 1)
            holder.newSilentAnnotation(HighlightSeverity.INFORMATION).range(markerRange).textAttributes(GigaToolsAttributesKeys.PROPERTY_KEY).create()

            // won't be empty or null otherwise it wouldn't match the pattern
            val property = match.groups[1]!!
            val propertyRange = TextRange.from(element.textRange.startOffset + property.range.first, property.range.last - property.range.first + 1)
            val propertyName = property.value

            if (validTags.containsKey(propertyName)) {
                holder
                    .newAnnotation(HighlightSeverity.INFORMATION, validTags[propertyName]?.fullDesc ?: "")
                    .range(propertyRange)
                    .textAttributes(GigaToolsAttributesKeys.PROPERTY_NAME_KEY)
                    .create()
            } else {
                holder
                    .newAnnotation(HighlightSeverity.WARNING, "Unknown tag \"$propertyName\" for type $elementType")
                    .range(propertyRange)
                    .highlightType(ProblemHighlightType.LIKE_UNKNOWN_SYMBOL)
                    .create()
            }
        }

        //println("ANNOTATED: $text")
    }

    fun register(disposable: Disposable) {
        LanguageAnnotators.INSTANCE.addExplicitExtension(ParadoxScriptLanguage, this)
        disposable.whenDisposed {
            LanguageAnnotators.INSTANCE.removeExplicitExtension(ParadoxScriptLanguage, this)
        }
    }
}

object DefinitionPropertyCompletionContributor : CompletionContributor() {
    init {
        extend(CompletionType.BASIC, PlatformPatterns.psiElement(PsiComment::class.java),
            object: CompletionProvider<CompletionParameters>() {
                override fun addCompletions(parameters: CompletionParameters, context: ProcessingContext, resultSet: CompletionResultSet) {
                    // get the comment element
                    val comment = parameters.position

                    // find the next element and check that it's a definition
                    val nextElement = GigaPsiUtils.nextNonWhiteSpaceSibling(comment)
                    if (nextElement !is ParadoxScriptDefinitionElement) { return }
                    // get the valid tags for the definition's type
                    val elementType = nextElement.definitionInfo?.typeConfig?.name ?: "unknown"
                    val validTags = ToolData.definitionTags[elementType] ?: return

                    // add all valid tags to the list, along with their descriptions
                    resultSet.addAllElements(validTags.keys.map { s -> LookupElementBuilder.create(s).withTypeText( validTags[s]?.shortDesc ) })
                }
            })
    }

    fun register(disposable: Disposable) {
        val languageExtension = CompletionContributor::class.java.getStaticField<LanguageExtension<CompletionContributor>>("INSTANCE")
        languageExtension.addExplicitExtension(ParadoxScriptLanguage, this, disposable)
    }
}

// init everything
runBlocking {
    // load data first, threaded, but blocking here
    ToolData.loadDataFile(project!!)

    // register menu group
    val pluginActionGroupId = "gigas.group"
    val pluginActionGroup = DefaultActionGroup("Gigas", true)
    pluginActionGroup.addTextOverride("MainMenu", "Gigastructures")
    registerAction(pluginActionGroupId, "", ActionGroupIds.Menu.Tools, pluginActionGroup)

    // register list rebuild action
    GigaRegenMegaCategoryLists.register(pluginActionGroupId)

    // register annotator
    DefinitionPropertyAnnotator.register(pluginDisposable)

    // register code completion
    DefinitionPropertyCompletionContributor.register(pluginDisposable)

    println("registered")
}


