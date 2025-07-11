import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/string
import grille_pain
import grille_pain/lustre/toast
import grille_pain/toast/level
import lustre
import lustre/attribute.{attribute}
import lustre/effect.{type Effect}
import lustre/element as lustre_element
import lustre/element/svg
import lustre/event
import sketch
import sketch/css.{class}
import sketch/css/length
import sketch/css/transform
import sketch/lustre as sketch_lustre
import sketch/lustre/element.{type Element}
import sketch/lustre/element/html

import plinth/browser/document
import plinth/browser/element as browser_element

pub fn main() {
  let assert Ok(_) = grille_pain.simple()
  let assert Ok(stylesheet) = sketch_lustre.setup()

  sketch.global(stylesheet, css.global("body", []))

  let app = lustre.application(init, update, view(_, stylesheet))

  let assert Ok(_) =
    lustre.start(
      app,
      "#app",
      Model(
        loading: False,
        notebook: None,
        notebooks: [
          NoteBook(
            name: "test repo",
            password: "wjdaiwwdaoiwda",
            room: "iasjjkadijdiw",
            publish_url: Some("url"),
          ),
          NoteBook(
            name: "test repo",
            password: "wjdaiwwdaoiwda",
            room: "sadsdgdfgdgf",
            publish_url: None,
          ),
          NoteBook(
            name: "test repo",
            password: "wjdaiwwdaoiwda",
            room: "dfsdfsdfsdfs",
            publish_url: Some("url"),
          ),
          NoteBook(
            name: "test repo",
            password: "wjdaiwwdaoiwda",
            room: "iasjjkadidfsdsfjdiw",
            publish_url: Some("url"),
          ),
        ],
        peers: [],
        selected_rooms: [],
        selected_document: None,
        modal: False,
        filesystem_menu: None,
        add_notebook_menu: False,
        loro_doc: None,
        tree: None,
        dragged_over_tree_item: None,
        edited_tree_item: None,
        selected_item_name: None,
        expanded_folders: [],
      ),
    )

  Nil
}

type Model {
  Model(
    peers: List(String),
    loading: Bool,
    selected_document: Option(String),
    notebook: Option(NoteBook),
    notebooks: List(NoteBook),
    selected_rooms: List(String),
    modal: Bool,
    add_notebook_menu: Bool,
    filesystem_menu: Option(List(String)),
    loro_doc: Option(LoroDoc),
    tree: Option(Node),
    dragged_over_tree_item: Option(String),
    edited_tree_item: Option(String),
    selected_item_name: Option(String),
    expanded_folders: List(String),
  )
}

fn init(model: Model) -> #(Model, Effect(Msg)) {
  #(model, init_tiptap())
}

pub opaque type Msg {
  SaveDocument
  ToggleModal
  DisplayNotebooks(List(NoteBook))
  EnterNotebook(NoteBook)
  DisplayBasicToast(String)
  DisplayErrorToast(String)

  DisplaySelectedRooms(List(String))

  LoroDocCreated(LoroDoc)
  UserDraggedItemOver(String)
  UserDraggedItemOff(String)
  RenderTree(Node)
  UserDroppedItem(String, String)
  DeleteItem(String)
  UserEditingItem(String)
  UserFinishedEditingItem(String)
  UserCanceledEditingItem
  ItemNameHasChanged(String)
  ToggleFolderExpanded(String)
  DoNothing
  DisplayFileSystemMenu(String, String)
  CreateNewNote(String)
  CreateNewFolder(String)
  HideFileSystemMenu
  UserSelectedNote(String)
  DownloadNoteBook
  ToggleLoading
  ToggleAddNotebookMenu
  RemoveNotebook(NoteBook)
  EditNotebook(NoteBook)
  ShareNotebook(NoteBook)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    DoNothing -> #(model, effect.none())
    ToggleAddNotebookMenu -> {
      #(
        Model(..model, add_notebook_menu: !model.add_notebook_menu),
        effect.none(),
      )
    }
    RemoveNotebook(removed_notebook) -> {
      let notebooks = model.notebooks

      let notebooks =
        notebooks
        |> list.filter(fn(notebook) { notebook.room != removed_notebook.room })
      #(Model(..model, notebooks:), effect.none())
    }
    EditNotebook(_notebook) -> #(model, effect.none())
    ShareNotebook(_notebook) -> #(model, effect.none())

    ToggleLoading -> {
      #(Model(..model, loading: !model.loading), effect.none())
    }
    DownloadNoteBook -> {
      case model.loro_doc {
        Some(loro_doc) -> {
          #(model, download_notebook(loro_doc))
        }
        None -> #(model, effect.none())
      }
    }
    UserSelectedNote(note_id) -> {
      #(
        Model(..model, filesystem_menu: None, selected_document: Some(note_id)),
        user_selected_note(note_id),
      )
    }
    HideFileSystemMenu -> {
      #(Model(..model, filesystem_menu: None), effect.none())
    }
    DisplayFileSystemMenu(item_id, y) -> {
      #(Model(..model, filesystem_menu: Some([item_id, y])), effect.none())
    }
    CreateNewNote(item_id) -> {
      case model.loro_doc {
        Some(loro_doc) -> {
          #(
            Model(..model, filesystem_menu: None),
            create_new_note(loro_doc, item_id),
          )
        }
        None -> {
          #(model, effect.none())
        }
      }
    }
    CreateNewFolder(item_id) -> {
      case model.loro_doc {
        Some(loro_doc) -> {
          #(
            Model(..model, filesystem_menu: None),
            create_new_folder(loro_doc, item_id),
          )
        }
        None -> {
          #(model, effect.none())
        }
      }
    }
    DeleteItem(item_id) ->
      case model.loro_doc {
        Some(loro_doc) -> #(model, delete_item(loro_doc, item_id))
        None -> #(model, effect.none())
      }
    UserCanceledEditingItem -> #(
      Model(..model, selected_item_name: None, edited_tree_item: None),
      effect.none(),
    )

    ToggleFolderExpanded(folder_id) -> {
      let folder_id_list = model.expanded_folders

      case folder_id_list |> list.contains(folder_id) {
        True -> {
          let expanded_folders =
            folder_id_list |> list.filter(fn(id) { id != folder_id })
          #(
            Model(..model, filesystem_menu: None, expanded_folders:),
            init_dnd(),
          )
        }
        False -> {
          let expanded_folders = folder_id_list |> list.append([folder_id])
          #(
            Model(..model, filesystem_menu: None, expanded_folders:),
            init_dnd(),
          )
        }
      }
    }

    ItemNameHasChanged(name) -> {
      #(Model(..model, selected_item_name: Some(name)), effect.none())
    }

    UserEditingItem(item_id) -> #(
      Model(..model, edited_tree_item: Some(item_id)),
      effect.none(),
    )

    UserFinishedEditingItem(item_id) -> {
      case model.loro_doc {
        Some(loro_doc) -> {
          case model.selected_item_name {
            Some(selected_item_name) -> {
              let trimmed_name = selected_item_name |> string.trim()
              #(
                Model(..model, selected_item_name: None),
                change_item_name(loro_doc, item_id, trimmed_name),
              )
            }
            None -> #(
              Model(..model, selected_item_name: None, edited_tree_item: None),
              effect.none(),
            )
          }
        }
        None -> #(model, effect.none())
      }
    }

    LoroDocCreated(loro_doc) -> #(
      Model(..model, loro_doc: Some(loro_doc)),
      effect.none(),
    )
    UserDraggedItemOver(id) -> #(
      Model(..model, dragged_over_tree_item: Some(id)),
      effect.none(),
    )
    UserDroppedItem(item, folder) -> {
      #(Model(..model, dragged_over_tree_item: None), case model.loro_doc {
        Some(loro_doc) -> {
          move_item(loro_doc, item, folder)
        }

        None -> {
          effect.none()
        }
      })
    }
    UserDraggedItemOff(id) -> {
      #(
        case model.dragged_over_tree_item {
          Some(dragged_item) -> {
            case dragged_item == id {
              True -> Model(..model, dragged_over_tree_item: None)
              False -> model
            }
          }
          None -> model
        },
        effect.none(),
      )
    }
    RenderTree(root) -> {
      case model.tree {
        Some(_old_tree) -> {
          #(Model(..model, tree: Some(root)), init_dnd())
        }
        None -> {
          #(Model(..model, tree: Some(root)), init_dnd())
        }
      }
    }

    SaveDocument -> #(model, save_document())
    ToggleModal -> #(Model(..model, modal: !model.modal), effect.none())

    EnterNotebook(notebook) -> {
      #(Model(..model, notebook: Some(notebook)), init_tiptap())
    }
    DisplayNotebooks(notebooks) -> #(Model(..model, notebooks:), effect.none())
    DisplaySelectedRooms(selected_rooms) -> #(
      Model(..model, selected_rooms:),
      effect.none(),
    )
    DisplayBasicToast(content) -> #(model, success_toast(content))
    DisplayErrorToast(content) -> #(
      Model(..model, loading: False),
      error_toast(content),
    )
  }
}

fn view(model: Model, stylesheet) -> Element(Msg) {
  use <- sketch_lustre.render(stylesheet:, in: [sketch_lustre.node()])

  case model.notebook {
    Some(_) -> {
      [
        case model.add_notebook_menu {
          True -> add_notebook_menu(model)
          False -> element.none()
        },
        notebooks_view(model),
      ]
      |> element.fragment
    }
    None -> {
      notebook_editor_view(model)
    }
  }
}

type LoroDoc

fn init_dnd() {
  use dispatch, _ <- effect.after_paint

  let tree_items: array.Array(browser_element.Element) =
    document.query_selector_all(".tree-item")

  let tree_item_list = tree_items |> array.to_list

  let filtered_drop_items =
    tree_item_list
    |> list.filter(fn(drop_item_element) {
      case
        drop_item_element
        |> browser_element.get_attribute("data-drop-target-for-element")
      {
        Ok(_) -> {
          False
        }
        Error(_) -> True
      }
    })
    |> array.from_list

  do_make_drop_target(
    folders: filtered_drop_items,
    on_drag_enter: fn(item_id) { dispatch(UserDraggedItemOver(item_id)) },
    on_drag_leave: fn(item_id) { dispatch(UserDraggedItemOff(item_id)) },
    on_drop: fn(item, folder) { dispatch(UserDroppedItem(item, folder)) },
  )

  let tree_item_list = tree_items |> array.to_list

  let filtered_tree_items =
    tree_item_list
    |> list.filter(fn(tree_item_element) {
      case tree_item_element |> browser_element.get_attribute("draggable") {
        Ok(_) -> False
        Error(_) -> True
      }
    })
    |> array.from_list

  do_make_draggable(filtered_tree_items)
}

fn add_notebook_menu(model: Model) {
  html.form(
    class([
      css.position("fixed"),
      css.top(length.px(0)),
      css.left(length.px(0)),
      css.width(length.percent(100)),
      css.height(length.percent(100)),
      css.background_color("rgba(0, 0, 0, 0.8)"),
      css.backdrop_filter("blur(8px)"),
      css.display("flex"),
      css.justify_content("center"),
      css.align_items("center"),
      css.z_index(1000),
      css.overflow_y("auto"),
      css.padding(length.px(24)),
    ]),
    [event.stop_propagation(event.on_click(ToggleAddNotebookMenu))],
    [
      html.div(
        class([
          css.background(" rgb(26 26 46) "),
          css.border_radius(length.px(16)),
          css.padding(length.px(32)),
          css.border("1px solid rgb(61, 61, 142)"),
          css.box_shadow(
            "0 20px 60px rgba(0, 0, 0, 0.7), 0 8px 32px rgba(0, 0, 0, 0.5)",
          ),
          css.min_width(length.px(450)),
          css.max_width(length.px(550)),
          css.width(length.percent(100)),
          css.max_height(length.percent(90)),
          css.overflow_y("auto"),
        ]),
        [event.stop_propagation(event.on_click(DoNothing))],
        [
          html.div(
            class([
              css.display("flex"),
              css.justify_content("space-between"),
              css.align_items("center"),
              css.margin_bottom(length.px(24)),
              css.padding_bottom(length.px(16)),
              css.border("2px solid rgb(61, 61, 142)"),
            ]),
            [],
            [
              html.h2(
                class([
                  css.font_size(length.px(28)),
                  css.font_weight("800"),
                  css.color("#f8fafc"),
                  css.margin(length.px(0)),
                  css.letter_spacing("-0.025em"),
                  css.background("linear-gradient(135deg, #3b82f6, #8b5cf6)"),
                  css.property("-webkit-background-clip", "text"),
                  css.property("-webkit-text-fill-color", "transparent"),
                  css.property("background-clip", "text"),
                ]),
                [],
                [html.text("Add New Notebook")],
              ),
              html.button(
                class([
                  css.background_color("rgba(255, 255, 255, 0.1)"),
                  css.border("none"),
                  css.color("#cbd5e1"),
                  css.font_size(length.px(28)),
                  css.cursor("pointer"),
                  css.padding(length.px(8)),
                  css.border_radius(length.px(8)),
                  css.transition("all 0.2s ease"),
                  css.hover([
                    css.background_color("rgba(255, 255, 255, 0.2)"),
                    css.color("#f8fafc"),
                    css.transform_("scale(1.1)"),
                  ]),
                ]),
                [
                  attribute.type_("button"),
                  event.on_click(ToggleAddNotebookMenu),
                ],
                [html.text("×")],
              ),
            ],
          ),
          html.div(
            class([
              css.display("flex"),
              css.flex_direction("column"),
              css.gap(length.px(20)),
            ]),
            [],
            [
              html.div(
                class([
                  css.display("flex"),
                  css.flex_direction("column"),
                  css.gap(length.px(20)),
                ]),
                [],
                [
                  form_field(
                    "Notebook Name",
                    "text",
                    "Enter notebook name...",
                    True,
                  ),
                  form_field("Room", "text", "Enter room name...", True),
                  form_field("Password", "password", "Enter password...", True),
                  html.div(
                    class([
                      css.display("flex"),
                      css.flex_direction("column"),
                      css.gap(length.px(16)),
                      css.padding(length.px(16)),
                      css.background_color("rgba(59, 130, 246, 0.05)"),
                      css.border_radius(length.px(12)),
                      css.border("1px solid rgb(61, 61, 142)"),
                    ]),
                    [],
                    [
                      form_field(
                        "GitHub Owner",
                        "text",
                        "Enter GitHub username/organization...",
                        False,
                      ),
                      form_field(
                        "Repository",
                        "text",
                        "Enter repository name...",
                        False,
                      ),
                      form_field(
                        "Branch",
                        "text",
                        "Enter branch name (e.g., main)...",
                        False,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          html.div(
            class([
              css.display("flex"),
              css.gap(length.px(16)),
              css.justify_content("flex-end"),
              css.margin_top(length.px(24)),
              css.padding_top(length.px(20)),
              css.border("1px solid rgb(61, 61, 142)"),
            ]),
            [],
            [
              button("Cancel", "#64748b", "#475569", ToggleAddNotebookMenu),
              button(
                "Create Notebook",
                "#10b981",
                "#059669",
                ToggleAddNotebookMenu,
              ),
            ],
          ),
        ],
      ),
    ],
  )
}

fn form_field(
  label: String,
  input_type: String,
  placeholder: String,
  required: Bool,
) -> Element(a) {
  html.div(
    class([
      css.display("flex"),
      css.flex_direction("column"),
      css.gap(length.px(8)),
    ]),
    [],
    [
      html.label(
        class([
          css.font_size(length.px(16)),
          css.font_weight("600"),
          css.color("#f1f5f9"),
          css.margin_bottom(length.px(4)),
        ]),
        [],
        [html.text(label)],
      ),
      html.input(
        class([
          css.padding(length.px(14)),
          css.border_radius(length.px(12)),
          css.border("2px solid rgb(61, 61, 142)"),
          css.background_color("#0f172a"),
          css.color("#f8fafc"),
          css.font_size(length.px(16)),
          css.transition("all 0.2s ease"),
          css.focus([
            css.outline("none"),
            css.border_color("#3b82f6"),
            css.box_shadow("0 0 0 3px rgba(59, 130, 246, 0.2)"),
          ]),
          css.hover([css.border_color("#475569")]),
        ]),
        [
          attribute.type_(input_type),
          attribute.placeholder(placeholder),
          attribute.required(required),
        ],
      ),
    ],
  )
}

fn button(
  text: String,
  bg_color: String,
  hover_color: String,
  on_click_msg: a,
) -> Element(a) {
  html.button(
    class([
      css.padding_("12px 24px"),
      css.background_color(bg_color),
      css.color("#ffffff"),
      css.border("none"),
      css.border_radius(length.px(12)),
      css.font_weight("600"),
      css.font_size(length.px(16)),
      css.cursor("pointer"),
      css.transition("all 0.2s ease"),
      css.box_shadow("0 4px 12px rgba(0, 0, 0, 0.3)"),
      css.hover([
        css.background_color(hover_color),
        css.transform_("translateY(-2px)"),
        css.box_shadow("0 6px 20px rgba(0, 0, 0, 0.4)"),
      ]),
      css.active([css.transform_("translateY(0)")]),
    ]),
    [attribute.type_("button"), event.on_click(on_click_msg)],
    [html.text(text)],
  )
}

fn notebook_editor_view(model: Model) {
  element.fragment([
    case model.modal {
      True -> {
        html.div(
          class([
            css.position("fixed"),
            css.top(length.rem(0.8)),
            css.right(length.rem(0.8)),
            css.padding(length.rem(1.0)),
            css.background("rgb(26 26 46)"),
            css.border_radius(length.px(16)),
            css.backdrop_filter("blur(16px)"),
            css.border("1px solid rgb(61, 61, 142)"),
            css.z_index(100),
          ]),
          [],
          [
            html.div(
              class([
                css.display("flex"),
                css.direction("rtl"),
                css.flex_direction("row"),
                css.gap(length.rem(0.75)),
              ]),
              [],
              [
                html.button(
                  class([
                    css.z_index(200),
                    css.display("flex"),
                    css.align_items("center"),
                    css.justify_content("center"),
                    css.width(length.rem(3.0)),
                    css.height(length.rem(3.0)),
                    css.background(
                      "linear-gradient(135deg, rgba(220, 38, 127, 0.9), rgba(180, 28, 100, 0.9))",
                    ),
                    css.border("1px solid rgb(61, 61, 142)"),
                    css.color("#ffffff"),
                    css.border_radius(length.px(12)),
                    css.cursor("pointer"),
                    css.font_size(length.rem(1.3)),
                    css.font_weight("600"),
                    css.letter_spacing("0.5px"),
                    css.transition("all 0.3s cubic-bezier(0.4, 0, 0.2, 1)"),
                    css.box_shadow(
                      "0 6px 20px rgba(220, 38, 127, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.25)",
                    ),
                    css.hover([
                      css.background(
                        "linear-gradient(135deg, rgba(220, 38, 127, 1), rgba(240, 48, 140, 1))",
                      ),
                      css.transform([
                        transform.translate_y(length.px(-3)),
                        transform.scale(1.02, 1.08),
                      ]),
                      css.box_shadow(
                        "0 10px 30px rgba(220, 38, 127, 0.5), inset 0 1px 0 rgba(255, 255, 255, 0.35)",
                      ),
                      css.border("1px solid rgb(61, 61, 142)"),
                    ]),
                    css.active([
                      css.transform([transform.translate_y(length.px(-1))]),
                    ]),
                  ]),
                  [event.on_click(ToggleModal)],
                  [menu_svg(" #FFFFFF ")],
                ),
                html.button(
                  class([
                    css.z_index(200),
                    css.display("flex"),
                    css.align_items("center"),
                    css.justify_content("center"),
                    css.padding_right(length.rem(1.0)),
                    css.padding_left(length.rem(1.0)),
                    css.padding_top(length.rem(0.75)),
                    css.padding_bottom(length.rem(0.75)),
                    css.min_height(length.rem(2.5)),
                    css.background("#1a1a2ef2"),
                    css.border("1px solid rgb(61, 61, 142)"),
                    css.color("#ffffff"),
                    css.border_radius(length.px(12)),
                    css.cursor("pointer"),
                    css.font_size(length.rem(0.9)),
                    css.font_weight("600"),
                    css.letter_spacing("0.3px"),
                    css.transition("all 0.3s cubic-bezier(0.4, 0, 0.2, 1)"),
                    css.hover([
                      css.transform([
                        transform.translate_y(length.px(-3)),
                        transform.scale(1.02, 1.08),
                      ]),
                      css.border("1px solid rgb(61, 61, 142)"),
                    ]),
                    css.active([
                      css.transform([transform.translate_y(length.px(-1))]),
                    ]),
                  ]),
                  [event.on_click(SaveDocument)],
                  [html.text("Save The Notebook To The Room")],
                ),
                html.button(
                  class([
                    css.z_index(200),
                    css.display("flex"),
                    css.align_items("center"),
                    css.justify_content("center"),
                    css.padding_right(length.rem(1.0)),
                    css.padding_left(length.rem(1.0)),
                    css.padding_top(length.rem(0.75)),
                    css.padding_bottom(length.rem(0.75)),
                    css.min_height(length.rem(2.5)),
                    css.background("#1a1a2ef2"),
                    css.border("1px solid rgb(61, 61, 142)"),
                    css.color("#ffffff"),
                    css.border_radius(length.px(12)),
                    css.cursor("pointer"),
                    css.font_size(length.rem(0.9)),
                    css.font_weight("600"),
                    css.letter_spacing("0.3px"),
                    css.transition("all 0.3s cubic-bezier(0.4, 0, 0.2, 1)"),
                    css.hover([
                      css.transform([
                        transform.translate_y(length.px(-3)),
                        transform.scale(1.02, 1.08),
                      ]),
                      css.border("1px solid rgb(61, 61, 142)"),
                    ]),
                    css.active([
                      css.transform([transform.translate_y(length.px(-1))]),
                    ]),
                  ]),
                  [event.on_click(DownloadNoteBook)],
                  [html.text("Download The Notebook As a File")],
                ),
              ],
            ),
            case model.tree {
              Some(root) ->
                element.fragment([
                  tree_view(model, root),
                  case model.filesystem_menu {
                    Some([item_id, y]) -> {
                      let y =
                        int.parse(y)
                        |> result.lazy_unwrap(fn() { 0 })
                      html.div(
                        class([
                          css.top(length.px(y)),
                          css.position("absolute"),
                          css.background_color("rgb(3, 29, 40)"),
                          css.border("1px solid rgb(61, 61, 142)"),
                          css.border_radius(length.px(8)),
                          css.box_shadow("0 4px 12px rgba(0, 0, 0, 0.1)"),
                          css.padding(length.px(4)),
                          css.min_width(length.px(180)),
                          css.z_index(300),
                          css.font_family(
                            "system-ui, -apple-system, sans-serif",
                          ),
                          css.font_size(length.px(14)),
                        ]),
                        [],
                        [
                          html.button(
                            class([
                              css.display("flex"),
                              css.align_items("center"),
                              css.padding_left(length.px(8)),
                              css.padding_right(length.px(12)),
                              css.padding_top(length.px(8)),
                              css.padding_bottom(length.px(8)),
                              css.cursor("pointer"),
                              css.border_radius(length.px(4)),
                              css.border("none"),
                              css.background_color("transparent"),
                              css.color("#e2e8f0"),
                              css.transition("all 0.2s ease"),
                              css.width(length.percent(100)),
                              css.text_align("left"),
                              css.hover([
                                css.background_color("rgba(59, 130, 246, 0.1)"),
                                css.color("#3b82f6"),
                              ]),
                            ]),
                            [event.on_click(CreateNewNote(item_id))],
                            [
                              html.div(
                                class([
                                  css.width(length.px(16)),
                                  css.height(length.px(16)),
                                  css.margin_right(length.px(8)),
                                  css.display("flex"),
                                  css.align_items("center"),
                                  css.justify_content("center"),
                                ]),
                                [],
                                [html.text("📄")],
                              ),
                              html.text("New Note"),
                            ],
                          ),
                          html.button(
                            class([
                              css.display("flex"),
                              css.align_items("center"),
                              css.padding_left(length.px(8)),
                              css.padding_right(length.px(12)),
                              css.padding_top(length.px(8)),
                              css.padding_bottom(length.px(8)),
                              css.cursor("pointer"),
                              css.border_radius(length.px(4)),
                              css.border("none"),
                              css.background_color("transparent"),
                              css.color("#e2e8f0"),
                              css.transition("all 0.2s ease"),
                              css.width(length.percent(100)),
                              css.text_align("left"),
                              css.hover([
                                css.background_color("rgba(59, 130, 246, 0.1)"),
                                css.color("#3b82f6"),
                              ]),
                            ]),
                            [event.on_click(CreateNewFolder(item_id))],
                            [
                              html.div(
                                class([
                                  css.width(length.px(16)),
                                  css.height(length.px(16)),
                                  css.margin_right(length.px(8)),
                                  css.display("flex"),
                                  css.align_items("center"),
                                  css.justify_content("center"),
                                ]),
                                [],
                                [html.text("📁")],
                              ),
                              html.text("New Folder"),
                            ],
                          ),
                        ],
                      )
                    }
                    _ -> {
                      element.none()
                    }
                  },
                ])
              None -> element.none()
            },
          ],
        )
      }
      False -> {
        html.button(
          class([
            css.z_index(200),
            css.position("fixed"),
            css.display("flex"),
            css.top(length.rem(1.5)),
            css.right(length.rem(1.5)),
            css.align_items("center"),
            css.justify_content("center"),
            css.width(length.rem(3.0)),
            css.height(length.rem(3.0)),
            css.background(
              "linear-gradient(135deg, rgba(220, 38, 127, 0.9), rgba(180, 28, 100, 0.9))",
            ),
            css.border("2px solid rgb(61, 61, 142)"),
            css.color("#ffffff"),
            css.border_radius(length.px(10)),
            css.cursor("pointer"),
            css.font_size(length.rem(1.2)),
            css.font_weight("600"),
            css.letter_spacing("1px"),
            css.transition("all 0.3s cubic-bezier(0.4, 0, 0.2, 1)"),
            css.box_shadow(
              "0 4px 15px rgba(220, 38, 127, 0.4), inset 0 1px 0 rgba(255, 255, 255, 0.2)",
            ),
            css.hover([
              css.background(
                "linear-gradient(135deg, rgba(220, 38, 127, 1), rgba(240, 48, 140, 1))",
              ),
              css.transform([
                transform.translate_y(length.px(-2)),
                transform.scale(1.0, 1.05),
              ]),
              css.box_shadow(
                "0 8px 25px rgba(220, 38, 127, 0.6), inset 0 1px 0 rgba(255, 255, 255, 0.3)",
              ),
              css.border("2px solid rgb(61, 61, 142)"),
            ]),
            css.active([css.transform([transform.translate_y(length.px(0))])]),
          ]),
          [event.on_click(ToggleModal)],
          [menu_svg(" #FFFFFF ")],
        )
      }
    },
    lustre_element.unsafe_raw_html("", "div", [attribute.class("editor")], ""),
  ])
}

fn notebooks_view(model: Model) {
  let notebooks = model.notebooks

  html.div(
    class([
      css.padding(length.px(32)),
      css.display("flex"),
      css.flex_direction("column"),
      css.gap(length.px(24)),
      css.max_width(length.px(1200)),
      css.margin_("0 auto"),
      css.min_height(length.vh(100)),
      css.background("linear-gradient(135deg, #0f172a 0%, #1e293b 100%)"),
    ]),
    [],
    [
      html.div(
        class([
          css.display("flex"),
          css.justify_content("space-between"),
          css.align_items("center"),
          css.margin_bottom(length.px(32)),
          css.padding_bottom(length.px(24)),
          css.border("2px solid rgb(61, 61, 142)"),
        ]),
        [],
        [
          html.div(
            class([
              css.display("flex"),
              css.flex_direction("column"),
              css.gap(length.px(8)),
            ]),
            [],
            [
              html.h1(
                class([
                  css.font_size(length.px(36)),
                  css.font_weight("800"),
                  css.color("#f8fafc"),
                  css.margin(length.px(0)),
                  css.letter_spacing("-0.025em"),
                  css.background("linear-gradient(135deg, #3b82f6, #8b5cf6)"),
                  css.property("-webkit-background-clip", "text"),
                  css.property("-webkit-text-fill-color", "transparent"),
                  css.property("background-clip", "text"),
                ]),
                [],
                [html.text("My Notebooks")],
              ),
              html.p(
                class([
                  css.font_size(length.px(16)),
                  css.color("#94a3b8"),
                  css.margin(length.px(0)),
                ]),
                [],
                [html.text("Manage your local and GitHub notebooks")],
              ),
            ],
          ),
          primary_button("+ Add Notebook", ToggleAddNotebookMenu),
        ],
      ),
      html.div(
        class([
          css.display("grid"),
          css.grid_template_columns("repeat(auto-fill, minmax(380px, 1fr))"),
          css.gap(length.px(24)),
        ]),
        [],
        {
          use notebook <- list.map(notebooks)
          case notebook {
            NoteBook(name, _, _, publish_url: Some(_)) -> {
              card("#3b82f6", "#1e40af", [
                card_header(name, cloud_svg),
                info_section(notebook),
                action_buttons(notebook),
              ])
            }

            NoteBook(name, _, _, publish_url: None) -> {
              card("#10b981", "#047857", [
                card_header(name, folder_svg),
                info_section(notebook),
                action_buttons(notebook),
              ])
            }
          }
        },
      ),
    ],
  )
}

fn primary_button(text: String, on_click_msg: Msg) -> Element(Msg) {
  html.button(
    class([
      css.padding_("16px 32px"),
      css.background("linear-gradient(135deg, #3b82f6, #2563eb)"),
      css.color("#ffffff"),
      css.border("none"),
      css.border_radius(length.px(12)),
      css.font_weight("600"),
      css.font_size(length.px(16)),
      css.cursor("pointer"),
      css.display("flex"),
      css.align_items("center"),
      css.gap(length.px(8)),
      css.transition("all 0.2s ease"),
      css.box_shadow("0 4px 12px rgba(59, 130, 246, 0.3)"),
      css.hover([
        css.background("linear-gradient(135deg, #2563eb, #1d4ed8)"),
        css.transform_("translateY(-2px)"),
        css.box_shadow("0 6px 20px rgba(59, 130, 246, 0.4)"),
      ]),
      css.active([css.transform_("translateY(0)")]),
    ]),
    [event.on_click(on_click_msg)],
    [html.text(text)],
  )
}

fn card(
  border_color: String,
  hover_border_color: String,
  children: List(Element(c)),
) -> Element(c) {
  html.div(
    class([
      css.padding(length.px(24)),
      css.border_radius(length.px(16)),
      css.background("linear-gradient(135deg, #1e293b 0%, #334155 100%)"),
      css.border("2px solid rgb(61, 61, 142)"),
      css.box_shadow("0 8px 32px rgba(0, 0, 0, 0.3)"),
      css.transition("all 0.3s ease"),
      css.position("relative"),
      css.overflow("hidden"),
      css.hover([
        css.transform_("translateY(-4px)"),
        css.box_shadow("0 12px 40px rgba(0, 0, 0, 0.4)"),
        css.border_color(border_color),
      ]),
      css.before([
        css.content(""),
        css.position("absolute"),
        css.top(length.px(0)),
        css.left(length.px(0)),
        css.right(length.px(0)),
        css.height(length.px(4)),
        css.background(
          "linear-gradient(90deg, "
          <> border_color
          <> ", "
          <> hover_border_color
          <> ")",
        ),
      ]),
    ]),
    [],
    children,
  )
}

fn card_header(name: String, icon) -> Element(b) {
  html.div(
    class([
      css.display("flex"),
      css.justify_content("space-between"),
      css.align_items("flex-start"),
      css.margin_bottom(length.px(20)),
    ]),
    [],
    [
      html.div(
        class([
          css.display("flex"),
          css.flex_direction("column"),
          css.gap(length.px(12)),
        ]),
        [],
        [
          html.div(
            class([
              css.display("flex"),
              css.align_items("center"),
              css.gap(length.px(12)),
            ]),
            [],
            [
              icon(),
              html.h3(
                class([
                  css.font_size(length.px(24)),
                  css.font_weight("700"),
                  css.color("#f8fafc"),
                  css.margin(length.px(0)),
                  css.letter_spacing("-0.025em"),
                ]),
                [],
                [html.text(name)],
              ),
            ],
          ),
        ],
      ),
      html.button(
        class([
          css.padding_("10px 20px"),
          css.font_size(length.px(14)),
          css.font_weight("600"),
          css.border_radius(length.px(8)),
          css.background_color("rgb(6, 138, 96) "),
          css.color("#ffffff"),
          css.border("none"),
          css.cursor("pointer"),
          css.transition("all 0.2s ease"),
          css.hover([
            css.background_color("rgb(6, 123, 86)"),
            css.transform_("translateY(-1px)"),
          ]),
        ]),
        [],
        [html.text("Enter")],
      ),
    ],
  )
}

fn info_section(notebook: NoteBook) -> Element(f) {
  html.div(
    class([
      css.margin_bottom(length.px(20)),
      css.padding(length.px(16)),
      css.background_color("rgba(0, 0, 0, 0.2)"),
      css.border_radius(length.px(12)),
      css.border("1px solid rgb(61, 61, 142)"),
    ]),
    [],
    [
      html.div(
        class([
          css.font_size(length.px(16)),
          css.color("#f1f5f9"),
          css.font_weight("600"),
          css.margin_bottom(length.px(4)),
        ]),
        [],
        [html.text(notebook.name)],
      ),
      html.div(
        class([
          css.font_size(length.px(14)),
          css.color("#94a3b8"),
          css.font_family("monospace"),
        ]),
        [],
        [
          case notebook {
            NoteBook(name:, room:, password:, publish_url: Some(_)) -> {
              [
                html.text("room id:" <> room),
                html.br(class([]), []),
                html.text("room password:" <> password),
                html.br(class([]), []),
                html.text("publish url:" <> password),
              ]
              |> element.fragment
            }
            NoteBook(name:, room:, password:, publish_url: None) -> {
              [
                html.text("room id:" <> room),
                html.br(class([]), []),
                html.text("room password:" <> password),
              ]
              |> element.fragment
            }
          },
        ],
      ),
    ],
  )
}

fn action_buttons(notebook: NoteBook) -> Element(Msg) {
  html.div(
    class([
      css.display("flex"),
      css.gap(length.px(12)),
      css.justify_content("flex-end"),
    ]),
    [],
    [
      action_button("Share", "#3b82f6", "#2563eb", ShareNotebook(notebook)),
      action_button("Edit", "#f59e0b", "#d97706", EditNotebook(notebook)),
      action_button("Remove", "#ef4444", "#dc2626", RemoveNotebook(notebook)),
    ],
  )
}

fn action_button(
  text: String,
  bg_color: String,
  hover_color: String,
  on_click_msg: a,
) -> Element(a) {
  html.button(
    class([
      css.padding_("8px 16px"),
      css.background_color(bg_color),
      css.color("#ffffff"),
      css.border("none"),
      css.border_radius(length.px(8)),
      css.font_weight("600"),
      css.font_size(length.px(13)),
      css.cursor("pointer"),
      css.transition("all 0.2s ease"),
      css.box_shadow("0 2px 4px rgba(0, 0, 0, 0.1)"),
      css.hover([
        css.background_color(hover_color),
        css.transform_("translateY(-1px)"),
        css.box_shadow("0 4px 8px rgba(0, 0, 0, 0.2)"),
      ]),
      css.active([css.transform_("translateY(0)")]),
    ]),
    [event.on_click(on_click_msg)],
    [html.text(text)],
  )
}

@external(javascript, "./js/editor.ts", "make_drop_target")
fn do_make_drop_target(
  folders folders: array.Array(a),
  on_drag_enter on_drag_enter: fn(String) -> Nil,
  on_drag_leave on_drag_leave: fn(String) -> Nil,
  on_drop on_drop: fn(String, String) -> Nil,
) -> Nil

@external(javascript, "./js/editor.ts", "get_tree")
fn get_tree(
  loro_doc: LoroDoc,
  room_id: String,
  on_tree: fn(String) -> Nil,
) -> String

@external(javascript, "./js/editor.ts", "create_loro_doc")
fn create_loro_doc(room_id: String) -> Promise(LoroDoc)

@external(javascript, "./js/editor.ts", "move_item")
fn do_move_item(loro_doc: LoroDoc, item: String, folder: String) -> Nil

@external(javascript, "./js/editor.ts", "delete_item")
fn do_delete_item(loro_doc: LoroDoc, item: String) -> Nil

@external(javascript, "./js/editor.ts", "change_item_name")
fn do_change_item_name(
  loro_doc: LoroDoc,
  item: String,
  item_name: String,
  on_change_name: fn() -> Nil,
) -> Nil

@external(javascript, "./js/editor.ts", "make_draggable")
fn do_make_draggable(elements: array.Array(a)) -> Nil

pub type Node {
  Node(
    id: String,
    parent: Option(String),
    index: Int,
    meta: Dict(String, decode.Dynamic),
    children: List(Node),
  )
}

pub fn node_decoder() {
  use id <- decode.field("id", decode.string)
  use parent <- decode.optional_field(
    "parent",
    None,
    decode.optional(decode.string),
  )
  use index <- decode.field("index", decode.int)
  use meta <- decode.field("meta", decode.dict(decode.string, decode.dynamic))
  use children <- decode.optional_field(
    "children",
    [],
    decode.list(node_decoder()),
  )

  decode.success(Node(
    id: id,
    parent: parent,
    index: index,
    meta: meta,
    children: children,
  ))
}

fn menu_svg(color color: String) -> Element(Msg) {
  html.svg(
    class([]),
    [
      attribute("xml:space", "preserve"),
      attribute("viewBox", "0 0 297 297"),
      attribute("xmlns:xlink", "http://www.w3.org/1999/xlink"),
      attribute("xmlns", "http://www.w3.org/2000/svg"),
      attribute.id("Layer_1"),
      attribute("version", "1.1"),
      attribute("width", "30px"),
      attribute("height", "30px"),
      attribute("fill", color),
    ],
    [
      svg.g([], [
        svg.g([], [
          svg.g([], [
            svg.path([
              attribute(
                "d",
                "M279.368,24.726H102.992c-9.722,0-17.632,7.91-17.632,17.632V67.92c0,9.722,7.91,17.632,17.632,17.632h176.376
				c9.722,0,17.632-7.91,17.632-17.632V42.358C297,32.636,289.09,24.726,279.368,24.726z",
              ),
            ]),
            svg.path([
              attribute(
                "d",
                "M279.368,118.087H102.992c-9.722,0-17.632,7.91-17.632,17.632v25.562c0,9.722,7.91,17.632,17.632,17.632h176.376
				c9.722,0,17.632-7.91,17.632-17.632v-25.562C297,125.997,289.09,118.087,279.368,118.087z",
              ),
            ]),
            svg.path([
              attribute(
                "d",
                "M279.368,211.448H102.992c-9.722,0-17.632,7.91-17.632,17.633v25.561c0,9.722,7.91,17.632,17.632,17.632h176.376
				c9.722,0,17.632-7.91,17.632-17.632v-25.561C297,219.358,289.09,211.448,279.368,211.448z",
              ),
            ]),
            svg.path([
              attribute(
                "d",
                "M45.965,24.726H17.632C7.91,24.726,0,32.636,0,42.358V67.92c0,9.722,7.91,17.632,17.632,17.632h28.333
				c9.722,0,17.632-7.91,17.632-17.632V42.358C63.597,32.636,55.687,24.726,45.965,24.726z",
              ),
            ]),
            svg.path([
              attribute(
                "d",
                "M45.965,118.087H17.632C7.91,118.087,0,125.997,0,135.719v25.562c0,9.722,7.91,17.632,17.632,17.632h28.333
				c9.722,0,17.632-7.91,17.632-17.632v-25.562C63.597,125.997,55.687,118.087,45.965,118.087z",
              ),
            ]),
            svg.path([
              attribute(
                "d",
                "M45.965,211.448H17.632C7.91,211.448,0,219.358,0,229.081v25.561c0,9.722,7.91,17.632,17.632,17.632h28.333
				c9.722,0,17.632-7.91,17.632-17.632v-25.561C63.597,219.358,55.687,211.448,45.965,211.448z",
              ),
            ]),
          ]),
        ]),
      ]),
    ],
  )
}

fn cloud_svg() {
  svg.svg(
    [
      attribute("xml:space", "preserve"),
      attribute("viewBox", "0 0 502.1 502.1"),
      attribute.id("Layer_1"),
      attribute("version", "1.1"),
      attribute("width", "40px"),
      attribute("height", "40px"),
      attribute("xmlns:xlink", "http://www.w3.org/1999/xlink"),
      attribute("xmlns", "http://www.w3.org/2000/svg"),
    ],
    [
      svg.ellipse([
        attribute("ry", "47.3"),
        attribute("rx", "190.7"),
        attribute("cy", "427.8"),
        attribute("cx", "261.5"),
        attribute(
          "style",
          "opacity:0.5;fill:#B8CBCD;enable-background:new    ;",
        ),
      ]),
      svg.path([
        attribute(
          "d",
          "M490,260.9c0-33.3-27-60.2-60.2-60.2c-2.7,0-5.3,0.2-7.8,0.6c0.2-2.1,0.3-4.1,0.3-6.2  c0-42.6-34.6-77.2-77.2-77.2c-10.1,0-19.7,2-28.5,5.5c-13.3-48.7-57.8-84.6-110.8-84.6c-61.6,0-111.9,48.6-114.7,109.5  c-44.4,3.8-79.2,40.9-79.2,86.3c0,45.3,34.8,82.4,79.1,86.2v0.3h342.6v-0.2C465,319,490,292.9,490,260.9z",
        ),
        attribute("style", "fill:#B9E3ED;"),
      ]),
      svg.path([
        attribute(
          "d",
          "M433.5,324.1H90.9c-0.6,0-1.2-0.2-1.6-0.5c-21.7-2.2-41.8-12.3-56.7-28.4  c-15.3-16.6-23.7-38.1-23.7-60.7s8.4-44.2,23.8-60.7C47.3,158,67,148,88.3,145.6c4-61.8,55.2-109.8,117.4-109.8  c51.9,0,97.8,34.2,112.8,83.6c8.6-3,17.5-4.6,26.5-4.6c44.2,0,80.2,36,80.2,80.2c0,1,0,1.9-0.1,2.8c1.6-0.1,3.1-0.2,4.6-0.2  c34.9,0,63.2,28.4,63.2,63.2c0,32.9-25.5,60.4-58.2,63C434.4,324,433.9,324.1,433.5,324.1z M92.3,318.1h340.1  c0.3-0.1,0.6-0.2,0.9-0.2c30.1-1.9,53.7-26.9,53.7-57c0-31.6-25.7-57.2-57.2-57.2c-2.2,0-4.6,0.2-7.5,0.5c-0.9,0.1-1.8-0.2-2.5-0.8  s-1-1.5-0.9-2.4c0.2-2,0.3-4,0.3-6c0-40.9-33.3-74.2-74.2-74.2c-9.4,0-18.6,1.8-27.4,5.3c-0.8,0.3-1.7,0.3-2.5-0.1  c-0.8-0.4-1.3-1.1-1.6-1.9c-13.2-48.5-57.6-82.4-107.9-82.4c-59.9,0-109,46.8-111.7,106.6c-0.1,1.5-1.2,2.7-2.7,2.9  c-42.9,3.6-76.4,40.2-76.4,83.3c0,43,33.5,79.6,76.3,83.3C91.6,317.8,92,317.9,92.3,318.1z",
        ),
        attribute("style", "fill:#324654;"),
      ]),
      svg.path([
        attribute(
          "d",
          "M40.7,236.4c8.2-39.2,36.2-63.2,77-66.6c2.6-56,48.8-100.7,105.4-100.7c26.1,0,49.9,9.5,68.3,25.2  C272.8,59.1,236,35,193.4,35c-59.5,0-108,46.9-110.7,105.7c-42.8,3.6-76.4,39.5-76.4,83.2c0,38.3,14.5,70.6,49.7,80.4  C36.6,282.5,36.3,257.5,40.7,236.4z",
        ),
        attribute("style", "fill:#FFFFFF;"),
      ]),
      svg.path([
        attribute(
          "d",
          "M471.5,211.9c2,6.1,3.2,12.5,3.2,19.3c0,32-25,58.1-56.5,60  v0.2H75.7v-0.3c-19.3,0-35.4,3.7-48.7-7.8c12.6,27.9,37.2,36.9,69.1,39.7h4h56h52h76h52h64h40h4c31.5-2,53.3-29.7,53.3-61.7  C497.3,240.9,487.1,222.8,471.5,211.9z",
        ),
        attribute(
          "style",
          "opacity:0.2;fill:#324654;enable-background:new    ;",
        ),
      ]),
      svg.polygon([
        attribute(
          "points",
          "364,259 301.7,196.9 240,259 280,259 280,383 324,383 324,259 ",
        ),
        attribute("style", "fill:#FFFFFF;"),
      ]),
      svg.g([], [
        svg.path([
          attribute(
            "d",
            "M324,392h-44c-5,0-9-4-9-9V268h-31c-3.6,0-6.9-2.2-8.3-5.5c-1.4-3.4-0.6-7.2,1.9-9.8l61.7-62.1   c1.7-1.7,4-2.7,6.4-2.7l0,0c2.4,0,4.7,0.9,6.4,2.6l62.3,62.1c2.6,2.6,3.4,6.4,2,9.8c-1.4,3.4-4.7,5.6-8.3,5.6h-31v115   C333,388,329,392,324,392z M289,374h26V259c0-5,4-9,9-9h18.2l-40.5-40.4L261.6,250H280c5,0,9,4,9,9L289,374L289,374z",
          ),
          attribute("style", "fill:#324654;"),
        ]),
        svg.path([
          attribute(
            "d",
            "M436,335H316v-24h119.6c23.8-1.7,42.4-23.6,42.4-50.1c0-26.6-21.6-48.2-48.2-48.2   c-1.8,0-3.8,0.1-6.3,0.5c-3.6,0.5-7.2-0.7-9.8-3.2c-2.6-2.5-4-6-3.7-9.6c0.1-1.8,0.3-3.6,0.3-5.3c0-35.9-29.2-65.2-65.2-65.2   c-8.2,0-16.3,1.6-24.1,4.7c-3.2,1.3-6.7,1.1-9.8-0.4c-3.1-1.5-5.3-4.3-6.2-7.6c-12.2-44.6-52.9-75.7-99.2-75.7   c-55.1,0-100.2,43.1-102.7,98.1c-0.3,6-5,10.9-11,11.4c-38.2,3.2-68.2,35.9-68.2,74.3c0,40.2,27.8,73,64.7,76.5h199.5v24h-200   c-0.3,0-0.7,0-1,0c-24.4-2.1-46.7-13.8-62.8-32.9C8.6,283.8,0,259.8,0,234.8c0-24.9,9.3-48.6,26.1-66.9c14.4-15.6,33.3-26,53.9-30   C87.8,74.9,141.3,27,205.8,27c52.8,0,99.9,33,118.5,81.5c6.8-1.7,13.8-2.5,20.8-2.5c47.1,0,85.8,36.7,89,82.9   c37.9,2.2,68,33.7,68,72.1c0,18.6-6.4,36.4-18,50.1c-12.2,14.4-28.9,22.9-47.2,24C436.5,335,436.2,335,436,335z",
          ),
          attribute("style", "fill:#324654;"),
        ]),
      ]),
      svg.polygon([
        attribute(
          "points",
          "112,359 173.7,419 236,359 196,359 196,235 152,235 152,359 ",
        ),
        attribute("style", "fill:#FFFFFF;"),
      ]),
      svg.path([
        attribute(
          "d",
          "M173.7,428c-2.3,0-4.5-0.8-6.3-2.5l-61.7-60c-2.6-2.6-3.4-6.4-2.1-9.8s4.7-5.6,8.3-5.6h31V235  c0-5,4-9,9-9h44c5,0,9,4,9,9v115h31c3.7,0,7,2.2,8.3,5.6c1.4,3.4,0.5,7.3-2.1,9.8l-62.3,60C178.2,427.2,176,428,173.7,428z   M134.2,368l39.6,38.5l39.9-38.5H196c-5,0-9-4-9-9V244h-26v115c0,5-4,9-9,9H134.2z",
        ),
        attribute("style", "fill:#324654;"),
      ]),
    ],
  )
}

fn folder_svg() {
  svg.svg(
    [
      attribute("xmlns:xlink", "http://www.w3.org/1999/xlink"),
      attribute("xmlns", "http://www.w3.org/2000/svg"),
      attribute("width", "40px"),
      attribute("viewBox", "0 0 2200 2200"),
      attribute("height", "40px"),
    ],
    [
      svg.defs([], [
        svg.linear_gradient(
          [
            attribute("y2", "100%"),
            attribute("y1", "0%"),
            attribute("x2", "100%"),
            attribute("x1", "0%"),
            attribute.id("folderTabGradient"),
          ],
          [
            svg.stop([
              attribute("stop-color", "#ffffff"),
              attribute("offset", "0%"),
            ]),
            svg.stop([
              attribute("stop-color", "#B9E3ED"),
              attribute("offset", "40%"),
            ]),
            svg.stop([
              attribute("stop-color", "#324654"),
              attribute("offset", "100%"),
            ]),
          ],
        ),
        svg.linear_gradient(
          [
            attribute("y2", "100%"),
            attribute("y1", "0%"),
            attribute("x2", "100%"),
            attribute("x1", "0%"),
            attribute.id("folderBodyGradient"),
          ],
          [
            svg.stop([
              attribute("stop-color", "#ffffff"),
              attribute("offset", "0%"),
            ]),
            svg.stop([
              attribute("stop-color", "#B9E3ED"),
              attribute("offset", "20%"),
            ]),
            svg.stop([
              attribute("stop-color", "#B8CBCD"),
              attribute("offset", "60%"),
            ]),
            svg.stop([
              attribute("stop-color", "#1a2832"),
              attribute("offset", "100%"),
            ]),
          ],
        ),
        svg.linear_gradient(
          [
            attribute("y2", "100%"),
            attribute("y1", "0%"),
            attribute("x2", "100%"),
            attribute("x1", "0%"),
            attribute.id("paperGradient"),
          ],
          [
            svg.stop([
              attribute("stop-color", "#ffffff"),
              attribute("offset", "0%"),
            ]),
            svg.stop([
              attribute("stop-color", "#f0f8fc"),
              attribute("offset", "100%"),
            ]),
          ],
        ),
        svg.radial_gradient(
          [
            attribute("r", "70%"),
            attribute.id("innerGlow"),
            attribute("cy", "30%"),
            attribute("cx", "50%"),
          ],
          [
            svg.stop([
              attribute("stop-opacity", "0.6"),
              attribute("stop-color", "#ffffff"),
              attribute("offset", "0%"),
            ]),
            svg.stop([
              attribute("stop-opacity", "0.3"),
              attribute("stop-color", "#ffffff"),
              attribute("offset", "40%"),
            ]),
            svg.stop([
              attribute("stop-opacity", "0"),
              attribute("stop-color", "#ffffff"),
              attribute("offset", "100%"),
            ]),
          ],
        ),
        lustre_element.namespaced(
          "http://www.w3.org/2000/svg",
          "filter",
          [
            attribute("y", "-50%"),
            attribute("x", "-50%"),
            attribute("width", "200%"),
            attribute.id("dropshadow"),
            attribute("height", "200%"),
          ],
          [
            svg.fe_gaussian_blur([
              attribute("stdDeviation", "15"),
              attribute("result", "blur"),
              attribute("in", "SourceAlpha"),
            ]),
            svg.fe_offset([
              attribute("result", "offsetBlur"),
              attribute("in", "blur"),
              attribute("dy", "12"),
              attribute("dx", "8"),
            ]),
            svg.fe_flood([
              attribute("flood-opacity", "0.4"),
              attribute("flood-color", "#1a2832"),
            ]),
            svg.fe_composite([
              attribute("operator", "in"),
              attribute("in2", "offsetBlur"),
            ]),
            svg.fe_merge([], [
              svg.fe_merge_node([]),
              svg.fe_merge_node([attribute("in", "SourceGraphic")]),
            ]),
          ],
        ),
        lustre_element.namespaced(
          "http://www.w3.org/2000/svg",
          "filter",
          [
            attribute("y", "-50%"),
            attribute("x", "-50%"),
            attribute("width", "200%"),
            attribute.id("innerShadow"),
            attribute("height", "200%"),
          ],
          [
            svg.fe_gaussian_blur([
              attribute("stdDeviation", "3"),
              attribute("result", "blur"),
              attribute("in", "SourceAlpha"),
            ]),
            svg.fe_offset([
              attribute("result", "offsetBlur"),
              attribute("in", "blur"),
              attribute("dy", "2"),
              attribute("dx", "0"),
            ]),
            svg.fe_flood([
              attribute("flood-opacity", "0.3"),
              attribute("flood-color", "#1a2832"),
            ]),
            svg.fe_composite([
              attribute("operator", "in"),
              attribute("in2", "offsetBlur"),
            ]),
            svg.fe_composite([
              attribute("operator", "in"),
              attribute("in2", "SourceGraphic"),
            ]),
          ],
        ),
        lustre_element.namespaced(
          "http://www.w3.org/2000/svg",
          "filter",
          [attribute.id("highlight")],
          [
            svg.fe_gaussian_blur([
              attribute("stdDeviation", "2"),
              attribute("result", "blur"),
              attribute("in", "SourceAlpha"),
            ]),
            svg.fe_offset([
              attribute("result", "offsetBlur"),
              attribute("in", "blur"),
              attribute("dy", "-1"),
              attribute("dx", "0"),
            ]),
            svg.fe_flood([
              attribute("flood-opacity", "0.3"),
              attribute("flood-color", "#ffffff"),
            ]),
            svg.fe_composite([
              attribute("operator", "in"),
              attribute("in2", "offsetBlur"),
            ]),
            svg.fe_merge([], [
              svg.fe_merge_node([attribute("in", "SourceGraphic")]),
              svg.fe_merge_node([]),
            ]),
          ],
        ),
      ]),
      svg.g(
        [attribute.id("folder-icon"), attribute("filter", "url(#dropshadow)")],
        [
          svg.path([
            attribute("stroke-width", "40"),
            attribute("stroke", "black"),
            attribute("fill", "url(#folderTabGradient)"),
            attribute(
              "d",
              "M205.898,1698.159c-2.714-7.933-4.194-16.437-4.194-25.292V472.901 c0-43.027,34.873-77.901,77.901-77.901h525.452c25.499,0,50.116,9.387,69.15,26.356l141.766,126.485 c19.034,16.969,43.637,26.356,69.15,26.356h591.503c43.027,0,77.901,34.873,77.901,77.901v101.569L205.898,1698.159z",
            ),
          ]),
          svg.path([
            attribute("stroke", "black"),
            attribute(
              "d",
              "M333,1275V703.023c0-17.255,13.985-31.241,31.241-31.241h1246.04 c17.255,0,31.241,13.985,31.241,31.241v493.047L333,1275z",
            ),
          ]),
          svg.path([
            attribute("stroke-width", "40"),
            attribute("stroke", "rgba(26, 40, 50, 0.3)"),
            attribute("fill", "url(#paperGradient)"),
            attribute(
              "d",
              "M361,1311V739.023c0-17.255,13.985-31.241,31.241-31.241h1246.04 c17.255,0,31.241,13.985,31.241,31.241v493.047L361,1311z",
            ),
          ]),
          svg.path([
            attribute("stroke-width", "4"),
            attribute("stroke", "#1a2832"),
            attribute("fill", "url(#folderBodyGradient)"),
            attribute(
              "d",
              "M1995.405,852.428l-248.311,893.404c-9.719,34.969-41.561,59.168-77.856,59.168H282.56 c-53.33,0-92.034-50.749-77.929-102.179l207.051-754.959c9.28-33.839,40.038-57.297,75.126-57.297h665.039 c18.541,0,36.744-4.963,52.719-14.374l183.59-108.15c15.975-9.411,34.178-14.374,52.719-14.374h479.475 C1971.872,753.667,2009.202,802.788,1995.405,852.428z",
            ),
          ]),
          svg.path([
            attribute("fill", "url(#innerGlow)"),
            attribute(
              "d",
              "M1995.405,852.428l-248.311,893.404c-9.719,34.969-41.561,59.168-77.856,59.168H282.56 c-53.33,0-92.034-50.749-77.929-102.179l207.051-754.959c9.28-33.839,40.038-57.297,75.126-57.297h665.039 c18.541,0,36.744-4.963,52.719-14.374l183.59-108.15c15.975-9.411,34.178-14.374,52.719-14.374h479.475 C1971.872,753.667,2009.202,802.788,1995.405,852.428z",
            ),
          ]),
          svg.path([
            attribute("stroke-width", "40"),
            attribute("stroke", "black"),
            attribute("fill", "none"),
            attribute(
              "d",
              "M1995.405,852.428l-248.311,893.404c-9.719,34.969-41.561,59.168-77.856,59.168H282.56 c-53.33,0-92.034-50.749-77.929-102.179l207.051-754.959c9.28-33.839,40.038-57.297,75.126-57.297h665.039 c18.541,0,36.744-4.963,52.719-14.374l183.59-108.15c15.975-9.411,34.178-14.374,52.719-14.374h479.475 C1971.872,753.667,2009.202,802.788,1995.405,852.428z",
            ),
          ]),
        ],
      ),
    ],
  )
}

fn backup_svg() {
  svg.svg(
    [
      attribute("xml:space", "preserve"),
      attribute("style", "enable-background:new 0 0 2200 2200;"),
      attribute("viewBox", "0 0 2200 2200"),
      attribute("y", "0px"),
      attribute("x", "0px"),
      attribute("version", "1.1"),
      attribute("xmlns:xlink", "http://www.w3.org/1999/xlink"),
      attribute("xmlns", "http://www.w3.org/2000/svg"),
    ],
    [
      svg.g([attribute.id("background")], [
        svg.rect([
          attribute("height", "2200"),
          attribute("width", "2200"),
          attribute("style", "fill:#FFFFFF;"),
        ]),
      ]),
      svg.g([attribute.id("Objects")], [
        svg.g([], [
          svg.path([
            attribute(
              "d",
              "M205.898,1698.159c-2.714-7.933-4.194-16.437-4.194-25.292V472.901    c0-43.027,34.873-77.901,77.901-77.901h525.452c25.499,0,50.116,9.387,69.15,26.356l141.766,126.485    c19.034,16.969,43.637,26.356,69.15,26.356h591.503c43.027,0,77.901,34.873,77.901,77.901v101.569L205.898,1698.159z",
            ),
            attribute("style", "fill:#EDAF00;"),
          ]),
          svg.path([
            attribute(
              "d",
              "M333,1275V703.023c0-17.255,13.985-31.241,31.241-31.241h1246.04    c17.255,0,31.241,13.985,31.241,31.241v493.047L333,1275z",
            ),
            attribute("style", "fill:#E8E8E8;"),
          ]),
          svg.path([
            attribute(
              "d",
              "M361,1311V739.023c0-17.255,13.985-31.241,31.241-31.241h1246.04    c17.255,0,31.241,13.985,31.241,31.241v493.047L361,1311z",
            ),
            attribute("style", "fill:#FFFFFF;"),
          ]),
          svg.path([
            attribute(
              "d",
              "M1995.405,852.428l-248.311,893.404c-9.719,34.969-41.561,59.168-77.856,59.168H282.56    c-53.33,0-92.034-50.749-77.929-102.179l207.051-754.959c9.28-33.839,40.038-57.297,75.126-57.297h665.039    c18.541,0,36.744-4.963,52.719-14.374l183.59-108.15c15.975-9.411,34.178-14.374,52.719-14.374h479.475    C1971.872,753.667,2009.202,802.788,1995.405,852.428z",
            ),
            attribute("style", "fill:#FFCE00;"),
          ]),
        ]),
      ]),
    ],
  )
}

@external(javascript, "./js/editor.ts", "download_notebook")
fn do_download_notebook(loro_doc: LoroDoc) -> Nil

fn download_notebook(loro_doc: LoroDoc) -> Effect(Msg) {
  use _ <- effect.from

  do_download_notebook(loro_doc)
}

@external(javascript, "./js/editor.ts", "user_selected_note")
fn do_user_selected_note(item_id: String) -> Nil

fn user_selected_note(item_id) -> Effect(Msg) {
  use _ <- effect.from
  do_user_selected_note(item_id)
}

fn create_new_note(loro_doc: LoroDoc, item_id: String) -> Effect(Msg) {
  use _ <- effect.from
  do_create_new_note(loro_doc, item_id)
}

@external(javascript, "./js/editor.ts", "create_new_note")
fn do_create_new_note(loro_doc: LoroDoc, item_id: String) -> Nil

fn create_new_folder(loro_doc: LoroDoc, item_id) -> Effect(Msg) {
  use _ <- effect.from
  do_create_new_folder(loro_doc, item_id)
}

@external(javascript, "./js/editor.ts", "create_new_folder")
fn do_create_new_folder(loro_doc: LoroDoc, item_id: String) -> Nil

fn change_item_name(loro_doc: LoroDoc, item_id, item_name) -> Effect(Msg) {
  use dispatch <- effect.from

  do_change_item_name(loro_doc, item_id, item_name, fn() {
    dispatch(UserCanceledEditingItem)
  })
}

fn delete_item(loro_doc: LoroDoc, item: String) -> Effect(Msg) {
  use _ <- effect.from

  do_delete_item(loro_doc, item)
}

fn move_item(loro_doc: LoroDoc, item: String, folder: String) -> Effect(Msg) {
  use _ <- effect.from

  do_move_item(loro_doc, item, folder)
}

@external(javascript, "./js/editor.ts", "save_document")
fn do_save_document() -> Nil

fn save_document() {
  use _ <- effect.from

  do_save_document()
}

@external(javascript, "./js/editor.ts", "init_tiptap")
fn do_init_tiptap(doc: LoroDoc) -> Nil

fn init_tiptap() {
  use dispatch, _ <- effect.after_paint

  promise.tap(create_loro_doc("noter"), fn(loro_doc) {
    dispatch(LoroDocCreated(loro_doc))

    get_tree(loro_doc, "noter", fn(tree) {
      let results = json.parse(from: tree, using: node_decoder())

      case results {
        Ok(root) -> {
          dispatch(RenderTree(root))
        }
        Error(error) -> {
          echo error
          Nil
        }
      }
    })

    do_init_tiptap(loro_doc)
  })

  Nil
}

fn success_toast(content: String) {
  toast.options()
  |> toast.level(level.Success)
  |> toast.custom(content)
}

fn error_toast(content) {
  toast.options()
  |> toast.timeout(10_000)
  |> toast.level(level.Error)
  |> toast.custom(content)
}

type NoteBook {
  NoteBook(
    name: String,
    room: String,
    password: String,
    publish_url: Option(String),
  )
}

pub type TreeItemType {
  Folder
  File
}

pub type TreeItem {
  TreeItem(
    id: String,
    name: String,
    item_type: TreeItemType,
    children: List(TreeItem),
  )
}

fn get_item_class(item_type: String) -> String {
  case item_type {
    "folder" -> "tree-item tree-folder"
    "file" -> "tree-item tree-file"
    _ -> panic
  }
}

fn get_expand_icon(item_type: String, is_expanded: Bool) -> String {
  case item_type {
    "folder" ->
      case is_expanded {
        True -> "▼"
        False -> "▶"
      }
    "file" -> ""
    _ -> panic
  }
}

fn get_item_icon(item_type: String) -> String {
  case item_type {
    "folder" -> "📁"
    "file" -> "📄"
    _ -> panic
  }
}

fn tree_item_view(
  is_root: Bool,
  item item: Node,
  model model: Model,
) -> Element(Msg) {
  let is_dragged = {
    case model.dragged_over_tree_item {
      Some(item_id) -> {
        item_id == item.id
      }
      None -> False
    }
  }

  let assert Ok(item_type_value) = item.meta |> dict.get("item_type")
  let assert Ok(item_type) = decode.run(item_type_value, decode.string)

  let name_value = item.meta |> dict.get("name")
  let name = {
    case name_value {
      Ok(name_value) -> {
        case decode.run(name_value, decode.string) {
          Ok(name) -> name
          Error(_) -> "Untitled"
        }
      }
      Error(_) -> "Untitled"
    }
  }

  let tree_item_classes = [
    attribute.classes([
      #(get_item_class(item_type), True),
      #("drop-target", is_dragged),
    ]),
    attribute.data("item_type", item_type),
    attribute.data("drag_id", item.id),
    case item.parent {
      Some(parent_id) -> attribute.data("parent_id", parent_id)
      None -> attribute.none()
    },
    case item_type {
      "folder" -> {
        event.on("click", {
          use y <- decode.field("clientY", decode.int)

          let y = int.to_string(y)

          decode.success(DisplayFileSystemMenu(item.id, y))
        })
      }
      "file" -> {
        event.on_click(UserSelectedNote(item.id))
      }
      _ -> attribute.none()
    },
  ]

  let file_system_menu_handler = case item_type {
    "folder" -> {
      event.stop_propagation(
        event.on("click", {
          use y <- decode.field("clientY", decode.int)
          let y = int.to_string(y)

          decode.success(DisplayFileSystemMenu(item.id, y))
        }),
      )
    }
    "file" -> {
      case item.parent {
        Some(parent_id) -> {
          event.stop_propagation(
            event.on("click", {
              use y <- decode.field("clientY", decode.int)

              let y = int.to_string(y)

              decode.success(DisplayFileSystemMenu(parent_id, y))
            }),
          )
        }
        None -> attribute.none()
      }
    }
    _ -> attribute.none()
  }

  html.div(
    class([]),
    case is_root {
      True -> {
        tree_item_classes
        |> list.append([
          attribute.class("root-node"),
          attribute.draggable(False),
          event.on("click", {
            use y <- decode.field("clientY", decode.int)

            let y = int.to_string(y)

            decode.success(DisplayFileSystemMenu(item.id, y))
          }),
        ])
      }
      False -> tree_item_classes
    },
    case is_root {
      True -> []

      False -> {
        [
          case item_type {
            "folder" -> {
              case item.children {
                [] -> element.none()
                _ -> {
                  html.span(
                    class([]),
                    [
                      event.stop_propagation(
                        event.on_click(ToggleFolderExpanded(item.id)),
                      ),
                      attribute.class("expand-icon"),
                    ],
                    [
                      html.text(get_expand_icon(
                        item_type,
                        model.expanded_folders |> list.contains(item.id),
                      )),
                    ],
                  )
                }
              }
            }
            "file" -> {
              element.none()
            }
            _ -> {
              element.none()
            }
          },
          html.span(class([]), [attribute.class("tree-icon")], [
            html.text(get_item_icon(item_type)),
          ]),
          {
            let default_item =
              html.span(class([]), [attribute.class("tree-name")], [
                html.text(name),
              ])

            case model.edited_tree_item {
              Some(item_id) -> {
                case item_id == item.id {
                  True -> {
                    html.input(class([]), [
                      attribute.class("tree-name"),
                      case model.selected_item_name {
                        Some(value) -> {
                          attribute.value(value)
                        }
                        None -> {
                          attribute.value(name)
                        }
                      },
                      event.on_input(ItemNameHasChanged),
                    ])
                  }
                  False -> {
                    default_item
                  }
                }
              }
              None -> {
                default_item
              }
            }
          },
          case model.edited_tree_item {
            Some(item_id) -> {
              case item_id == item.id {
                True -> {
                  element.fragment([
                    html.button(
                      class([]),
                      [
                        attribute.class("edit-button"),
                        event.stop_propagation(
                          event.on_click(UserFinishedEditingItem(item.id)),
                        ),
                      ],
                      [html.text("✅")],
                    ),
                    html.button(
                      class([]),
                      [
                        attribute.class("edit-button"),
                        event.stop_propagation(event.on_click(
                          UserCanceledEditingItem,
                        )),
                      ],
                      [html.text("❌")],
                    ),
                  ])
                }
                False ->
                  element.fragment([
                    html.button(
                      class([]),
                      [attribute.class("edit-button"), file_system_menu_handler],
                      [html.text("➕")],
                    ),
                    html.button(
                      class([]),
                      [
                        attribute.class("edit-button"),
                        event.stop_propagation(
                          event.on_click(UserEditingItem(item.id)),
                        ),
                      ],
                      [html.text("✏️")],
                    ),
                    html.button(
                      class([]),
                      [
                        attribute.class("edit-button"),
                        event.stop_propagation(
                          event.on_click(DeleteItem(item.id)),
                        ),
                      ],
                      [html.text("🗑️")],
                    ),
                  ])
              }
            }
            None ->
              element.fragment([
                html.button(
                  class([]),
                  [attribute.class("edit-button"), file_system_menu_handler],
                  [html.text("➕")],
                ),
                html.button(
                  class([]),
                  [
                    attribute.class("edit-button"),
                    event.stop_propagation(
                      event.on_click(UserEditingItem(item.id)),
                    ),
                  ],
                  [html.text("✏️")],
                ),
                html.button(
                  class([]),
                  [
                    attribute.class("edit-button"),
                    event.stop_propagation(event.on_click(DeleteItem(item.id))),
                  ],
                  [html.text("🗑️")],
                ),
              ])
          },
        ]
      }
    },
  )
}

fn tree_children_view(
  is_item_at_root: Bool,
  children: List(Node),
  model: Model,
) -> Element(Msg) {
  let get_item_info = fn(item: Node) {
    let assert Ok(type_value) = item.meta |> dict.get("item_type")
    let assert Ok(item_type) = decode.run(type_value, decode.string)

    let name = case item.meta |> dict.get("name") {
      Ok(value) -> {
        let assert Ok(name) = decode.run(value, decode.string)
        Some(name)
      }
      Error(_) -> None
    }

    #(item_type, name)
  }

  html.div(
    class([]),
    [
      case is_item_at_root {
        True -> {
          attribute.none()
        }
        False -> {
          attribute.class("tree-children")
        }
      },
    ],
    children
      |> list.sort(fn(a, b) {
        let #(a_type, a_name) = get_item_info(a)
        let #(b_type, b_name) = get_item_info(b)

        case a_type, b_type {
          "folder", "file" -> order.Lt
          "file", "folder" -> order.Gt
          _, _ -> {
            case a_name, b_name {
              Some(name_a), Some(name_b) -> string.compare(name_a, name_b)
              Some(_), None -> order.Lt
              None, Some(_) -> order.Gt
              None, None -> order.Eq
            }
          }
        }
      })
      |> list.map(fn(child) {
        let #(item_type, _) = get_item_info(child)

        case item_type {
          "folder" -> {
            [
              tree_item_view(False, child, model),
              case child.children {
                [] -> element.none()
                _ -> {
                  case model.expanded_folders |> list.contains(child.id) {
                    True -> tree_children_view(False, child.children, model)
                    False -> element.none()
                  }
                }
              },
            ]
          }
          "file" -> [tree_item_view(False, child, model)]
          _ -> panic
        }
      })
      |> list.flatten,
  )
}

fn tree_view(model: Model, tree: Node) -> Element(Msg) {
  html.div(class([]), [attribute.class("tree")], [
    case tree.children {
      [] -> element.none()
      _ -> tree_children_view(True, tree.children, model)
    },
    tree_item_view(True, tree, model),
  ])
}
