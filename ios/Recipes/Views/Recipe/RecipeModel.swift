import SwiftUI

/// State of one recipe page — the globals of recipe.html (`recipe`, `currentServings`,
/// `cookingMode`, `timers`, …) gathered in one place.
@MainActor
@Observable
final class RecipeModel {
    enum Phase { case loading, failed, loaded }

    let recipeID: Int
    var phase: Phase = .loading
    private(set) var recipe: Recipe?
    private(set) var nutrition: Nutrition?
    private(set) var timers: StepTimers?

    private(set) var baseServings = 1
    private(set) var currentServings = 1
    /// The web re-renders step text from `cleanStepText(text)` once servings change.
    private var servingsChanged = false

    var checkedIngredients: Set<Int> = []
    var openSteps: Set<Int> = []
    var doneSteps: Set<Int> = []
    private(set) var allOpen = true

    private(set) var cookingMode = false
    private(set) var cookingIndex = 0

    let recipeSpeech = SpeechClip()
    private var stepSpeech: [Int: SpeechClip] = [:]

    var noteDraft = ""

    init(recipeID: Int) {
        self.recipeID = recipeID
    }

    var ratio: Double { Double(currentServings) / Double(baseServings) }
    var steps: [RecipeStep] { recipe?.steps ?? [] }

    func load() async {
        guard recipe == nil else { return }
        phase = .loading
        do {
            let loaded = try await API.shared.recipe(id: recipeID)
            recipe = loaded
            baseServings = max(1, loaded.servings ?? 1)
            currentServings = baseServings
            openSteps = Set(loaded.steps.map(\.id))
            timers = StepTimers(recipeID: loaded.id, recipeTitle: loaded.title)
            phase = .loaded
            StepTimers.requestNotificationPermission()
            if let n = try? await API.shared.nutrition(recipeID: recipeID), n.calories != nil, n.calories != "0" {
                nutrition = n
            }
        } catch {
            phase = .failed
        }
    }

    // MARK: Servings

    enum Multiplier { case half, one, two }

    func setServings(_ value: Int) {
        guard value >= 1 else { return }
        currentServings = value
        servingsChanged = true
    }

    func applyMultiplier(_ m: Multiplier) {
        switch m {
        case .half: setServings(max(1, currentServings / 2))
        case .one: setServings(baseServings)
        case .two: setServings(currentServings * 2)
        }
    }

    // MARK: Step text

    func runs(for step: RecipeStep) -> [StepText.Run] {
        guard let recipe else { return [] }
        let source = servingsChanged ? StepText.clean(step.text) : step.text
        return StepText.runs(fromHTML: StepText.highlightHTML(source, ingredients: recipe.ingredients, ratio: ratio))
    }

    // MARK: Steps

    func toggleOpen(_ step: RecipeStep) {
        if openSteps.contains(step.id) { openSteps.remove(step.id) } else { openSteps.insert(step.id) }
    }

    /// "סגור את כל הצעדים" leaves only the first step open; "פתח את כל הצעדים" opens everything.
    func toggleAllSteps() {
        if allOpen {
            openSteps = Set(steps.prefix(1).map(\.id))
            allOpen = false
        } else {
            openSteps = Set(steps.map(\.id))
            allOpen = true
        }
    }

    /// Ticks the ingredient-list rows that a step's text mentions.
    private func markIngredientsDone(for step: RecipeStep) {
        guard let recipe else { return }
        for (index, ingredient) in recipe.ingredients.enumerated() where StepText.mentions(ingredient, in: step.text) {
            checkedIngredients.insert(index)
        }
    }

    func toggleDone(_ step: RecipeStep) {
        if doneSteps.contains(step.id) {
            doneSteps.remove(step.id)
        } else {
            doneSteps.insert(step.id)
            markIngredientsDone(for: step)
        }
    }

    // MARK: Cooking mode

    func isDimmed(_ index: Int) -> Bool { cookingMode && index != cookingIndex }

    func toggleCookingMode() {
        cookingMode.toggle()
        if cookingMode {
            cookingIndex = 0
            goToStep(0)
        } else {
            openSteps = Set(steps.map(\.id))
            allOpen = true
        }
    }

    /// Returns the id of the step to scroll to, if any.
    @discardableResult
    func goToStep(_ index: Int) -> Int? {
        let steps = steps
        if index < 0 { return nil }
        if index >= steps.count {
            // Finished: everything is done and cooking mode ends.
            doneSteps = Set(steps.map(\.id))
            toggleCookingMode()
            return nil
        }
        if index > cookingIndex, steps.indices.contains(cookingIndex) {
            doneSteps.insert(steps[cookingIndex].id)
            markIngredientsDone(for: steps[cookingIndex])
        }
        cookingIndex = index
        openSteps.insert(steps[index].id)
        return steps[index].id
    }

    var cookingProgress: Double {
        steps.isEmpty ? 0 : Double(cookingIndex) / Double(steps.count)
    }

    // MARK: Speech

    func speech(for step: RecipeStep) -> SpeechClip {
        if let clip = stepSpeech[step.id] { return clip }
        let clip = SpeechClip()
        stepSpeech[step.id] = clip
        return clip
    }

    /// `buildTTSText()`
    var fullSpeechText: String {
        guard let recipe else { return "" }
        var lines = ["מתכון: \(recipe.title)."]
        if let description = recipe.description, !description.isEmpty { lines.append(description) }
        lines.append("מרכיבים:")
        for ing in recipe.ingredients {
            var line = ing.label
            if let amount = ing.amount, !amount.isEmpty { line += ", " + amount }
            if let unit = ing.unit, !unit.isEmpty { line += " " + unit }
            lines.append(line + ".")
        }
        lines.append("הוראות הכנה:")
        for (i, step) in recipe.steps.enumerated() {
            var line = "שלב \(i + 1)"
            if let title = step.title, !title.isEmpty { line += ", " + title }
            lines.append(line + ". " + step.text)
        }
        return lines.joined(separator: " ")
    }

    func stopAllSpeech() {
        recipeSpeech.stop()
        stepSpeech.values.forEach { $0.stop() }
    }

    // MARK: Notes

    func addNote() async {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let note = try? await API.shared.addNote(recipeID: recipeID, text: text) else { return }
        recipe?.notes.insert(note, at: 0)
        noteDraft = ""
    }

    func deleteNote(_ note: RecipeNote) async {
        guard (try? await API.shared.deleteNote(recipeID: recipeID, noteID: note.id)) != nil else { return }
        recipe?.notes.removeAll { $0.id == note.id }
    }
}
