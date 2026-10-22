defmodule MealplanWeb.UITest do
  use ExUnit.Case, async: true

  import MealplanWeb.UI
  import Phoenix.Component
  import Phoenix.LiveViewTest

  defp html(rendered), do: rendered |> rendered_to_string() |> LazyHTML.from_fragment()
  defp query(doc, selector), do: LazyHTML.query(doc, selector)
  defp count(doc, selector), do: doc |> query(selector) |> Enum.count()
  defp text(doc, selector), do: doc |> query(selector) |> LazyHTML.text() |> String.trim()
  defp attrs(doc, selector, name), do: doc |> query(selector) |> LazyHTML.attribute(name)

  describe "page_header/1" do
    test "back link, full-width title, meta, actions and a menu" do
      assigns = %{}

      doc =
        html(~H"""
        <.page_header back="/recipes" back_label="Recipes">
          A very long recipe name that must wrap
          <:meta>Serves 6</:meta>
          <:actions><button id="edit">Edit</button></:actions>
          <:menu><a id="download" href="/x">Download</a></:menu>
        </.page_header>
        """)

      assert attrs(doc, "header a[href='/recipes']", "href") == ["/recipes"]
      assert text(doc, "header a[href='/recipes']") == "Recipes"
      assert text(doc, "h1") == "A very long recipe name that must wrap"
      assert text(doc, "h1 + p") == "Serves 6"
      assert count(doc, "#edit") == 1
      assert count(doc, "details#page-header-menu summary[aria-label='More actions']") == 1
      assert count(doc, "details#page-header-menu li #download") == 1
    end

    test "only a title" do
      assigns = %{}
      doc = html(~H"<.page_header>Recipes</.page_header>")

      assert text(doc, "h1") == "Recipes"
      assert count(doc, "a") == 0
      assert count(doc, "details") == 0
    end
  end

  test "section_card/1 labels the section by its title; danger marks it" do
    assigns = %{}

    doc =
      html(~H"""
      <.section_card id="slots" title="Meal slots" help="The times you plan for.">body</.section_card>
      <.section_card id="danger" title="Delete household" danger>bye</.section_card>
      """)

    assert attrs(doc, "#slots", "aria-labelledby") == ["slots-title"]
    assert text(doc, "#slots-title") == "Meal slots"
    assert text(doc, "#slots p") == "The times you plan for."
    assert doc |> attrs("#danger", "class") |> hd() =~ "border-error"
  end

  describe "list_row/1" do
    test "a link row, a button row and a plain row with actions" do
      assigns = %{}

      doc =
        html(~H"""
        <.row_list id="rows">
          <.list_row id="link" navigate="/recipes/1" title="Full name">
            Full name
            <:meta>Serves 4</:meta>
          </.list_row>
          <.list_row id="tick" phx-click="tick" phx-value-key="oats" aria-pressed="false">
            oats
            <:trailing>400 g</:trailing>
            <:lead><span class="box"></span></:lead>
          </.list_row>
          <.list_row id="plain">
            Breakfast
            <:actions><button id="rename">Rename</button></:actions>
          </.list_row>
        </.row_list>
        """)

      assert count(doc, "ul#rows > li") == 3
      assert attrs(doc, "#link a", "href") == ["/recipes/1"]
      assert attrs(doc, "#link a", "title") == ["Full name"]
      assert text(doc, "#link a .line-clamp-2") == "Full name"
      assert text(doc, "#link a span.block") == "Serves 4"

      assert attrs(doc, "#tick button", "phx-click") == ["tick"]
      assert attrs(doc, "#tick button", "phx-value-key") == ["oats"]
      assert count(doc, "#tick button .box") == 1
      assert text(doc, "#tick button .tabular-nums") == "400 g"

      assert count(doc, "#plain > div:first-child button") == 0
      assert count(doc, "#plain #rename") == 1
      assert count(doc, "#plain a") <= 0
    end
  end

  test "add_form/1 has a labelled field and an Add button" do
    assigns = %{form: to_form(%{"text" => ""}, as: :item)}

    doc =
      html(~H"""
      <.add_form
        for={@form}
        id="item-form"
        field={@form[:text]}
        label="Add an item"
        placeholder="e.g. Kitchen roll"
        phx-submit="add_item"
      />
      """)

    assert attrs(doc, "form#item-form", "phx-submit") == ["add_item"]
    assert attrs(doc, "label.sr-only", "for") == ["item_text"]
    assert attrs(doc, "input#item_text", "placeholder") == ["e.g. Kitchen roll"]
    assert text(doc, "button") == "Add"
  end

  test "confirm_panel/1 lists what is affected and sends the events" do
    assigns = %{}

    doc =
      html(~H"""
      <.confirm_panel
        id="del"
        title="Delete this meal?"
        confirm="Delete meal"
        on_confirm="confirm_delete"
        on_cancel="cancel_delete"
      >
        These days lose it:
        <:item>Thu 22 Oct, dinner</:item>
        <:item>Sun 25 Oct, dinner</:item>
      </.confirm_panel>
      """)

    assert attrs(doc, "#del", "role") == ["alertdialog"]
    assert text(doc, "#del-title") == "Delete this meal?"
    assert count(doc, "#del ul li") == 2
    assert attrs(doc, "#del-confirm", "phx-click") == ["confirm_delete"]
    assert text(doc, "#del-confirm") == "Delete meal"
    assert attrs(doc, "button.btn-ghost", "phx-click") == ["cancel_delete"]
  end

  test "empty_state/1 shows the message and its action" do
    assigns = %{}

    doc =
      html(~H"""
      <.empty_state id="none">
        No recipes yet.<:action><a href="/new">New recipe</a></:action>
      </.empty_state>
      """)

    assert text(doc, "#none p") == "No recipes yet."
    assert attrs(doc, "#none a", "href") == ["/new"]
  end

  test "chip_group/1 and chip/1 are pressed toggles" do
    assigns = %{}

    doc =
      html(~H"""
      <.chip_group label="Suits">
        <.chip pressed phx-click="toggle" phx-value-id="1">Lunch</.chip>
        <.chip pressed={false} phx-click="toggle" phx-value-id="2">Dinner</.chip>
      </.chip_group>
      """)

    assert attrs(doc, "[role=group]", "aria-label") == ["Suits"]
    assert attrs(doc, "button", "aria-pressed") == ["true", "false"]
    assert attrs(doc, "button", "phx-value-id") == ["1", "2"]
    assert count(doc, "button[aria-pressed=true] .hero-check") == 1
  end

  test "stepper/1 steps by one and stops at its limits" do
    assigns = %{}

    doc =
      html(~H"""
      <.stepper id="low" label="servings" value={1} event="adjust" />
      <.stepper id="high" label="servings" value={100} event="adjust" />
      """)

    assert attrs(doc, "#low button", "phx-value-delta") == ["-1", "1"]
    assert attrs(doc, "#low button", "aria-label") == ["Fewer servings", "More servings"]
    assert text(doc, "#low output") == "1"
    assert count(doc, "#low button[disabled]") == 1
    assert attrs(doc, "#low button[disabled]", "phx-value-delta") == ["-1"]
    assert attrs(doc, "#high button[disabled]", "phx-value-delta") == ["1"]
  end

  test "collapsible/1 keeps its body but hides it when closed" do
    assigns = %{}

    doc =
      html(~H"""
      <.collapsible id="ticked" title="Ticked" count={3} open={false} on_toggle="toggle" value="ticked">
        <p id="inside">oats</p>
      </.collapsible>
      """)

    assert attrs(doc, "#ticked > button", "aria-expanded") == ["false"]
    assert attrs(doc, "#ticked > button", "aria-controls") == ["ticked-body"]
    assert attrs(doc, "#ticked > button", "phx-value-group") == ["ticked"]
    assert text(doc, "#ticked > button") =~ "(3)"
    assert doc |> attrs("#ticked-body", "class") |> hd() =~ "hidden"
    assert count(doc, "#inside") == 1
  end

  test "sheet/1 is a labelled modal dialog that closes three ways" do
    assigns = %{}

    doc =
      html(~H"""
      <.sheet id="plan-sheet" title="Add to Dinner" on_close="close_sheet">body</.sheet>
      """)

    assert attrs(doc, "[role=dialog]", "aria-labelledby") == ["plan-sheet-title"]
    assert attrs(doc, "[role=dialog]", "aria-modal") == ["true"]
    assert text(doc, "#plan-sheet-title") == "Add to Dinner"
    assert attrs(doc, "#plan-sheet", "phx-window-keydown") == ["close_sheet"]
    assert attrs(doc, "button[aria-label=Close]", "phx-click") == ["close_sheet"]
    assert attrs(doc, "[aria-hidden=true].bg-black\\/40", "phx-click") == ["close_sheet"]
  end
end
