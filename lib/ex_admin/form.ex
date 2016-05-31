defmodule ExAdmin.Form do
  @moduledoc """
  Override the default new and edit form pages for an ExAdmin resource.

  By default, ExAdmin renders the form page without any additional
  configuration. It renders each column in the model, except the id,
  inserted_at, and updated_at columns in an attributes table.

  To customize the new and edit pages, use the `form` macro.

  For example, the following will show on the id an name fields, as
  well place a selection column and batch actions row on the page:

      defmodule MyProject.ExAdmin.Contact do
        use ExAdmin.Register

        register_resource MyProject.Contact do

          form contact do
            inputs do
              input contact, :first_name
              input contact, :last_name
              input contact, :email
              input contact, :category, collection: MyProject.Category.all
            end

            inputs "Groups" do
              inputs :groups, as: :check_boxes, collection: MyProject.Group.all
            end
          end
        end
      end

  ## The form command

  Call form with a name for your resource and a do block.

  ## The inputs command

  Calling inputs with a do block displays a field set with the specified inputs
  from the block.

  Adding a label to inputs, labels the field set.

  ## The input command

  The first argument is input is alway the resource name give to the form
  command. The second argument is the the field name expressed as an atom.
  Optionally, a third argument can be a keyword list.

  ### Override the default label

      input resource, :name, label: "Customer Name"

  ### Specify a collection

      input resource, :category, collection: Repo.all(Category)

  ### Specify the field names for a collection

      input resource, :user, fields: [:first_name, :email]

  ### Specifying type of control

      input user, :password, type: :password

  ### Customizing DateTime fields

      input user, :start_at, options: [sec: []]

  Most of the options from the `datetime_select` control from
  `phoenix_html` should work.

  ## Rendering a has_many relationship

  The example at the beginning of the chapter illustrates how to add
  a list of roles, displaying them as check boxes.

      inputs "Groups" do
        inputs :groups, as: :check_boxes, collection: MyProject.Group.all
      end

  ## Nested attributes

  ExAdmin supports in-line creation of a has_many relationship. The
  example below allows the user to add/delete phone numbers on the
  contact form using the has_many command.

      form contact do
        inputs do
          input contact, :first_name
          input contact, :last_name
          input contact, :email
          input contact, :category, collection: UcxNotifier.Category.all
        end

        inputs "Phone Numbers" do
          has_many contact, :phone_numbers, fn(p) ->
            input p, :label, collection: PhoneNumber.labels
            input p, :number
          end
        end
      end

  # Adding conditional fields

  The following complicated example illustrates a number of concepts
  possible in a form definition. The example allows management of an
  authentication token for a user while on the edit page.

  First, the `if params[:id] do` condition ensures that the code block
  only executes for an edit form, and not a new form.

  Next, the actions command adds in-line actions to an inputs block.
  TODO: is this correct??

      form user do
        inputs "User Details" do
          input user, :name
          # ...
        end

        if params[:id] do
          inputs "Authentication Token" do
            actions do
              user = Repo.get User, params[:id]
              if user.authentication_token do
                content content_tag(:li, user.authentication_token, style: "padding: 5px 10px")
                content content_tag(:li, token_link("Reset Token", :reset, params[:id]), class: "cancel")
                content content_tag(:li, token_link("Delete Token", :delete, params[:id]), class: "cancel")
              else
                content content_tag(:li, token_link("Create Token", :create, params[:id]),
                  class: "cancel", style: "padding-left: 20px")
              end
            end
          end
        end

      end

  ## The javascript command

  Use the javascript command to add javascript to the form page.

  For example, the following adds a change handler to get a list of
  assets using an ajax call:

      javascript do
        \"""
        $(document).ready(function() {
          $('#asset_assetable_type_id').change(function() {
            $.get('/assets/'+$(this).val()+'/assetables?format=js');
          });
        });
        \"""
      end
  """

  require Logger
  import ExAdmin.Utils
  import ExAdmin.Helpers
  import ExAdmin.DslUtils
  import ExAdmin.Form.Fields
  import ExAdmin.ViewHelpers, only: [escape_javascript: 1]
  require IEx
  import ExAdmin.Theme.Helpers
  alias ExAdmin.Schema

  import Kernel, except: [div: 2]
  use Xain
  import Xain, except: [input: 2, input: 1]

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      import Xain, except: [input: 1]
    end
  end

  ################
  # DSL Macros

  @doc """
  Customize the form page.

  Use the form command to customize the new and edit page forms. Pass
  a name for the resource to be created or modified.
  """
  defmacro form(resource, [do: block]) do
    contents = quote do
      unquote(block)
    end

    quote location: :keep, bind_quoted: [resource: escape(resource), contents: escape(contents)] do
      def form_view(var!(conn), unquote(resource) = var!(resource), var!(params) = params) do
        import ExAdmin.Register, except: [actions: 1]

        var!(input_blocks, ExAdmin.Form) = []
        var!(script_block, ExAdmin.Form) = nil
        unquote(contents)
        items = var!(input_blocks, ExAdmin.Form) |> Enum.reverse
        script_block = var!(script_block, ExAdmin.Form)
        Module.concat(var!(conn).assigns.theme, Form).build_form(
          var!(conn), var!(resource), items, var!(params), script_block)
      end

      def get_blocks(var!(conn), unquote(resource) = var!(resource), var!(params) = _params) do
        # TODO: do we need the passed params? they are not used.
        _ = {var!(conn), var!(resource), var!(params)}
        import ExAdmin.Register, except: [actions: 1]
        var!(input_blocks, ExAdmin.Form) = []
        var!(script_block, ExAdmin.Form) = nil
        unquote(contents)
        var!(input_blocks, ExAdmin.Form) |> Enum.reverse
      end

      def ajax_view(conn, params, resources, block) do
        defn = conn.assigns.defn
        resource = defn.resource_model.__struct__
        field_name = String.to_atom params[:field_name]
        model_name = model_name(resource)
        ext_name = ext_name model_name, field_name
        if is_function(block[:opts][:collection]) do
          resources = block[:opts][:collection].(conn, resource)
        end
        view = markup do
          ExAdmin.Form.Fields.input_collection(resource, resources, model_name, field_name, params[:id1], params[:nested2], block, conn.params)
        end

        ~s/$('##{ext_name}-update').html("#{escape_javascript(view)}");/
      end
    end
  end

  @doc """
  Add an fieldset to the form
  """
  defmacro inputs(opts) do
    quote(do: inputs("", unquote(opts)))
  end

  @doc """
  Add a has_many field to a form.
  """
  defmacro inputs(name, opts, do: block) do
    quote location: :keep do
      import Xain, except: [input: 1]
      # inputs_save = var!(inputs, ExAdmin.Form)
      var!(inputs, ExAdmin.Form) = []
      unquote(block)
      items = var!(inputs, ExAdmin.Form) |> Enum.reverse
      # var!(inputs, ExAdmin.Form) = inputs_save
      input_block = %{type: :inputs, name: unquote(name), inputs: items, opts: unquote(opts)}
      var!(input_blocks, ExAdmin.Form) = [input_block | var!(input_blocks, ExAdmin.Form)]
    end

  end

  @doc """
  Add a named fieldset to a form.

  Works the same as inputs/1, but labels the fieldset with name
  """
  defmacro inputs(name, do: block) do
    quote location: :keep do
      import Xain, except: [input: 1]
      # inputs_save = var!(inputs, ExAdmin.Form)
      var!(inputs, ExAdmin.Form) = []
      unquote(block)
      items = var!(inputs, ExAdmin.Form) |> Enum.reverse
      # var!(inputs, ExAdmin.Form) = inputs_save
      input_block = %{type: :inputs, name: unquote(name), inputs: items, opts: []}
      var!(input_blocks, ExAdmin.Form) = [input_block | var!(input_blocks, ExAdmin.Form)]
    end
  end

  @doc """
  Add a has_many field to a form.
  """
  defmacro inputs(name, opts) do
    quote location: :keep do
      import Xain, except: [input: 1]
      opts = Enum.into unquote(opts), %{}
      item = %{type: :inputs, name: unquote(name), opts: opts}
      var!(inputs, ExAdmin.Form) = [item | var!(inputs, ExAdmin.Form)]
    end
  end

  @doc """
  Display an input field on the form.

  Display all types of form inputs.

  ## Options

    * `:type` - Sets the type of the control (`:password`, `:hidden`, etc)

    * `:label` - Sets a custom label

    * `:collection` - Sets the collection to render for a `belongs_to` relationship

    * `:fields` - Sets a list of fields to be used in a select control.
      For example `input post :user, fields: [:first_name, :last_name]`
      would render a control like:

          `<select>`
            `<option id="1">José Valim</option>`
            `<option id="2">Chris McCord</option>
          `</select>`

    * `:prompt` - Sets a HTML placeholder

    * `:change` - Sets change handler to a control. When set to a string,
      the string is assumed to be javascript and added with the control.
      When a keyword list, the list is used to define what should happen
      when the input changes. See the section below on valid keywords.

    * `:ajax` - Used for ajax controls. See ajax below

    * `:display` - When set to false, the control and its label are
      hidden with `style="display: none"`. Use this to hide inputs
      that will later be displayed with javascript or an ajax request

    * `:as` - Sets the type of collection. Valid options are:
      * `:check_boxes` - Use check boxes
      * `:radio - Use radio buttons

  ## Ajax controls

  Use the ajax: true, change: [...] do allow dynamic updating of
  nested collection inputs.

  For example, assume a page for purchasing
  a product, where the product has a number of options and each option
  has different possible color selections.

  When option 1 is selected, they have the choice of red or black. If
  option 2 is selected, they have the choice of red or green. So, based
  on the option selected, the color select needs to be dynamically reloaded.

  TBD: Complete this



  """
  defmacro input(resource, name, opts \\ []) do
    quote do
      opts = Enum.into unquote(opts), %{}
      item = %{type: :input, resource: unquote(resource), name: unquote(name), opts: opts}
      var!(inputs, ExAdmin.Form) = [item | var!(inputs, ExAdmin.Form)]
    end
  end

  @doc """
  Display a nested resource on the form.

  Adds management of a has_many resource to the page, allowing in-line
  addition, editing, and deletion of the nested resource.

  """
  defmacro has_many(resource, name, opts \\ [], fun \\ nil) do
    quote do
      opts = ExAdmin.DslUtils.fun_to_opts unquote(opts), unquote(fun)
      item = %{type: :has_many, resource: unquote(resource), name: unquote(name), opts: opts}
      var!(inputs, ExAdmin.Form) = [item | var!(inputs, ExAdmin.Form)]
    end
  end

  @doc """
  Add an action block to a form

  TBD: Add more description here
  """
  defmacro actions(do: block) do
    quote do
      var!(inputs, ExAdmin.Form) = []
      var!(items, ExAdmin.Form) = []
      unquote(block)
      items = var!(items, ExAdmin.Form) |> Enum.reverse
      item = %{type: :actions, name: "", items: items}
      var!(inputs, ExAdmin.Form) = [item | var!(inputs, ExAdmin.Form)]
    end
  end

  @doc """
  Add a HTML content block to a form

  For example:

      content do
        \"""
        <div>Something here</div>
        <div>More stuff here</div>
        \"""
      end
  """
  defmacro content(do: block) do
    quote do
      contents = unquote(block)
      item = %{type: :content, name: "", content: unquote(block), opts: []}
      var!(inputs, ExAdmin.Form) = [item | var!(inputs, ExAdmin.Form)]
    end
  end

  @doc """
  Add HTML content to a form.

  Can be called multiple times to append HTML content for a page

  For example:

      content content_tag(:li, user.authentication_token, style: "padding: 5px 10px")
      content content_tag(:li, token_link("Reset Token", :reset, params[:id]), class: "cancel")
      content content_tag(:li, token_link("Delete Token", :delete, params[:id]), class: "cancel")

  """
  defmacro content(items, opts \\ quote(do: [])) do
    quote do
      item = %{type: :content, content: unquote(items), opts: unquote(opts)}
      var!(items, ExAdmin.Form) = [item | var!(items, ExAdmin.Form)]
    end
  end

  @doc """
  Add javascript to the form

  Adds a block of javascript code to the form. Typically used to add
  change or click handlers to elements on the page
  """
  defmacro javascript(do: block) do
    quote do
      var!(script_block, ExAdmin.Form) = unquote(block)
    end
  end

  #################
  # Functions

  defp build_item(resource, defn, name) do
     #Logger.warn "build_item 10...."
    case translate_field defn, name do
      field when field == name ->
        %{type: :input, resource: resource, name: name, opts: %{}}
      field ->
        case resource.__struct__.__schema__(:association, field) do
          %Ecto.Association.BelongsTo{cardinality: :one, queryable: assoc} ->
            collection = Application.get_env(:ex_admin, :repo).all assoc
            %{type: :input, resource: resource, name: field, opts: %{collection: collection}}
          _ ->
            nil
        end
    end
  end

  def setup_resource(resource, params, model_name) do
    model_name = String.to_atom(model_name)
    case params[model_name] do
      nil -> resource
      model_params ->
        struct(resource, Map.to_list(model_params))
    end
  end

  def put_script_block(script_block) do
    if script_block do
      Xain.text "\n"
      Xain.script type: "text/javascript" do
        text "\n" <> script_block <> "\n"
      end
    end
  end

  def build_scripts(list) do
    head = "$(function() {\n"
    script = for i <- list, is_tuple(i), into: head, do: build_script(i)
    script <> "});"
  end

  def build_script({:change, %{id: id, script: script}}) do
    """
    $(document).on('change','##{id}', function() {
      #{script}
    });
    """
  end
  def build_script(_other), do: ""

  def get_action(resource, mode) do
    case mode do
      :new ->
        admin_resource_path(resource, :create)
      :edit ->
        admin_resource_path(resource, :update)
    end
  end
  defp get_put_fields(:edit) do
    Xain.input(name: "_method", value: "put", type: "hidden")
  end
  defp get_put_fields(_), do: nil

  def build_hidden_block(_conn, mode) do
    csrf = Plug.CSRFProtection.get_csrf_token
    div style: "margin:0;padding:0;display:inline" do
      Xain.input(name: "utf8", type: :hidden, value: "✓")
      Xain.input(type: :hidden, name: "_csrf_token", value: csrf)
      get_put_fields(mode)
    end
  end

  def build_main_block(conn, resource, model_name, schema) do
    errors = Phoenix.Controller.get_flash(conn, :inline_error)
    for item <- schema do
      item = put_in item, [:required], conn.assigns[:ea_required] || []
      build_item(conn, item, resource, model_name, errors)
    end
    |> flatten
  end

  defp flatten(list) when is_list(list), do: List.flatten(list)
  defp flatten(other), do: [other]

  @hidden_style [style: "display: none"]

  defp check_display(opts) do
    if Map.get(opts, :display, true), do: [], else: @hidden_style
  end

  defp check_params(display_style, resource, params, model_name, field_name, _ajax) do
    cond do
      params["id"] -> []
      params[model_name][params_name(resource, field_name, params)] -> []
      true -> display_style
    end
  end

  defp field_type(resource, field_name) do
    resource.__struct__.__schema__(:type, field_name)
  end

  defp params_name(resource, field_name, _params) do
    case resource.__struct__.__schema__(:association, field_name) do
      %{cardinality: :one, owner_key: owner_key} ->
        Atom.to_string(owner_key)
      %{cardinality: :many, owner_key: owner_key, through: [_, name]} ->
        Atom.to_string(name) <> "_" <> Inflex.pluralize(Atom.to_string(owner_key))
      _ ->
        Atom.to_string(field_name)
    end
  end

  @doc false
  def wrap_item(resource, field_name, model_name, label, error, opts, params, required, contents) do
    as = Map.get opts, :as
    ajax = Map.get opts, :ajax
    ext_name = ext_name(model_name, field_name)

    display_style = check_display(opts)
    |> check_params(resource, params, model_name, field_name, ajax)

    {label, hidden}  = case label do
      {:hidden, l} -> {l, @hidden_style}
      l when l in [:none, false] ->  {"", @hidden_style}
      l -> {l, display_style}
    end
    error = if error in [nil, [], false], do: "", else: "error "

    theme_module(Form).theme_wrap_item(field_type(resource, field_name), ext_name, label, hidden,
      ajax, error, contents, as, required)
    ext_name
  end


  def wrap_item_type(type, label, ext_name, contents, error, required) do
    ExAdmin.theme.wrap_item_type(type, label, ext_name, contents, error, required)
  end


  defp build_select_binary_tuple_list(collection, item, field_name, resource, model_name, ext_name) do
    html_opts = item[:opts][:html_opts] || []
    html_opts = Dict.merge([name: "#{model_name}[#{field_name}]"], html_opts)
    select("##{ext_name}_id.form-control", html_opts) do
      handle_prompt(field_name, item)
      for item <- collection do
        {value, name} = case item do
          {value, name} -> {value, name}
          other -> {other, other}
        end
        selected = if Map.get(resource, field_name) == value,
          do: [selected: :selected], else: []
        option(name, [value: value] ++ selected)
      end
    end
  end


  @doc false
  def build_item(_conn, %{type: :script, contents: contents}, _resource, _model_name, _errors) do
    script type: "javascript" do
      text "\n" <> contents <> "\n"
    end
  end

  @doc """
  Private: Build a belongs_to control.

  Generate a select box for a belongs_to control.
  """
  def build_item(conn, %{type: :input, name: field_name, resource: _resource,
       opts: %{collection: collection}} = item, resource, model_name, errors) do

    # IO.puts "build_item 3: #{inspect field_name}"
    if is_function(collection) do
      collection = collection.(conn, resource)
    end
    module = resource.__struct__
    errors_field_name = if field_name in module.__schema__(:associations) do
      Map.get module.__schema__(:association, field_name), :owner_key
    else
      field_name
    end
    required = if errors_field_name in (conn.assigns[:ea_required] || []), do: true, else: false
    errors = get_errors(errors, errors_field_name)

    label = Map.get item[:opts], :label, field_name
    onchange = Map.get item[:opts], :change

    binary_tuple = binary_tuple?(collection)

    id = wrap_item(resource, field_name, model_name, label, errors, item[:opts], conn.params, required, fn(ext_name) ->
      item = update_in item[:opts], &(Map.delete(&1, :change) |> Map.delete(:ajax))
      if binary_tuple do
        build_select_binary_tuple_list(collection, item, field_name, resource, model_name, ext_name)
      else
        input_collection(resource, collection, model_name, field_name, nil, nil, item, conn.params)
      end
      build_errors(errors)
    end)

    value = case onchange do
      script when is_binary(script) ->
        {:change, %{id: id <> "_id", script: onchange}}
      list when is_list(list) ->
        update = Keyword.get(list, :update)
        params = Keyword.get(list, :params)
        if update do
          route_path = admin_resource_path(resource.__struct__, :index)
          target = pluralize(field_name)
          nested = pluralize(update)

          # TODO: Need to fix this by looking it up
          resource_name = pluralize model_name

          {extra, param_str} =
          case params do
            atom when is_atom(atom) -> extra_javascript(model_name, atom, atom)
            [{param, attr}]         -> extra_javascript(model_name, param, attr)
            _                       -> {"", ""}
          end

          control_id = "#{model_name}_#{update}_input"
          script = "$('##{control_id}').show();\n" <>
                   extra <>
                   "console.log('show #{control_id}');\n" <>
                   "$.get('#{route_path}/#{target}/'+$(this).val()+'/#{nested}/?field_name=#{update}#{param_str}&format=js');\n"

          {:change, %{id: id <> "_id", script: script}}
        end
      _ -> nil
    end
    if onchange, do: value
  end

  def build_item(conn, %{type: :actions, items: items}, resource, model_name, errors) do
    fieldset ".actions" do
      for i <- items do
        build_item(conn, i, resource, model_name, errors)
      end
    end
  end

  def build_item(_conn, %{type: :content, content: content}, _resource, _model_name, _errors) when is_binary(content) do
    text content
  end
  def build_item(_conn, %{type: :content, content: content}, _resource, _model_name, _errors) do
    text elem(content, 1)
  end

  def build_item(conn, %{type: :input, resource: _resource, name: field_name, opts: opts},
       resource, model_name, errors) do
    # IO.puts "build_item 4: #{inspect field_name}"
    errors = get_errors(errors, field_name)
    label = get_label(field_name, opts)
    required = if field_name in (conn.assigns[:ea_required] || []), do: true, else: false
    wrap_item(resource, field_name, model_name, label, errors, opts, conn.params, required, fn(ext_name) ->
      resource.__struct__.__schema__(:type, field_name)
      |> build_control(resource, opts, model_name, field_name, ext_name, errors)
    end)
  end

  def build_item(conn, %{type: :has_many, resource: _resource, name: field_name,
      opts: %{fun: fun}}, resource, model_name, errors) do
    # IO.puts "build_item 5: #{inspect field_name}"
    field_field_name = "#{field_name}_attributes"
    human_label = "#{humanize(field_name) |> Inflex.singularize}"
    new_record_name_var = new_record_name field_name
    div ".has_many.#{field_name}" do
      {_, html} = theme_module(conn, Form).build_inputs_has_many field_name, human_label, fn ->
        get_resource_field2(resource, field_name)
        |> Enum.with_index
        |> Enum.each(fn({res, inx}) ->
          fields = fun.(res) |> Enum.reverse
          ext_name = "#{model_name}_#{field_field_name}_#{inx}"

          new_inx = build_has_many_fieldset(conn, res, fields, inx, ext_name, field_name, field_field_name, model_name, errors)
          res_id = ExAdmin.Schema.get_id(res)

          Xain.input [id: "#{ext_name}_id",
            name: "#{model_name}[#{field_field_name}][#{new_inx}][id]",
            value: "#{res_id}", type: :hidden]
        end)
        markup :nested do
          ext_name = "#{model_name}_#{field_field_name}_#{new_record_name_var}"
          {assoc_model, _} = assoc_model_tuple = ExAdmin.Repo.get_assoc_model(resource, field_name)
          fields = fun.(assoc_model_tuple) |> Enum.reverse
          build_has_many_fieldset(conn, assoc_model.__struct__, fields, new_record_name_var, ext_name, field_name, field_field_name, model_name, errors)
        end
      end
      {_, onclick} = Phoenix.HTML.html_escape  theme_module(conn, Form).has_many_insert_item(html, new_record_name_var)
      theme_module(conn, Form).theme_button ".btn-primary Add New #{human_label}", href: "#", onclick: onclick
    end
  end

  @doc """
  Handle building an inputs :name, as: ...
  """
  def build_item(conn, %{type: :inputs, name: name, opts: %{collection: collection} = opts},
      resource, model_name, errors) when is_atom(name) do

    # IO.puts "build_item 6: #{inspect name}"
    if is_function(collection) do
      collection = collection.(conn, resource)
    end
    errors = get_errors(errors, name)
    name_ids = "#{Atom.to_string(name) |> Inflex.singularize}_ids"
    assoc_ids = Enum.map(get_resource_field2(resource, name), &(Schema.get_id(&1)))
    name_str = "#{model_name}[#{name_ids}][]"
    required = get_required name, opts
    theme_module(conn, Form).build_inputs_collection model_name, name, name_ids, required, fn ->
      Xain.input name: name_str, type: "hidden", value: ""
      if opts[:as] == :check_boxes do
        theme_module(conn, Form).wrap_collection_check_boxes fn ->
          for opt <- collection do
            opt_id = Schema.get_id(opt)
            name_str = "#{model_name}[#{name_ids}][#{opt_id}]"
            selected = opt_id in assoc_ids
            theme_module(conn, Form).collection_check_box opt.name, name_str, opt_id, selected
          end
        end
      else
        select id: "#{model_name}_#{name_ids}", class: "form-control", multiple: "multiple", name: name_str do
          for opt <- collection do
            opt_id = Schema.get_id(opt)
            selected = if opt_id in assoc_ids, do: [selected: "selected"], else: []
            option "#{opt.name}", [value: "#{opt_id}"] ++ selected
          end
        end
      end
      build_errors(errors)
    end
  end

  @doc false
  def build_item(conn, %{type: :inputs, name: _field_name} = item, resource, model_name, errors) do
    opts = Map.get(item, :opts, [])
    # IO.puts "build_item 7: #{inspect _field_name}"
    theme_module(conn, Form).form_box item, opts, fn ->
      theme_module(conn, Form).theme_build_inputs item, opts, fn ->
        for inpt <- item[:inputs] do
          build_item(conn, inpt, resource, model_name, errors)
        end
      end
    end
  end

  @doc false
  def build_control(:boolean, resource, opts, model_name, field_name, ext_name, errors) do
    Xain.input type: :hidden, value: "false", name: "#{model_name}[#{field_name}]"
    if Map.get(resource, field_name) do
      Map.put_new(opts, :checked, "checked")
    else
      opts
    end
    |> Map.put_new(:type, :checkbox)
    |> Map.put_new(:value, "true")
    |> Map.put_new(:name, "#{model_name}[#{field_name}]")
    |> Map.put_new(:id, ext_name)
    |> Map.to_list
    |> Xain.input
    build_errors(errors)
  end

  def build_control(Ecto.DateTime, resource, opts, model_name, field_name, _ext_name, errors) do
    %{name: model_name, model: resource, id: model_name, class: "form-control"}
    |> datetime_select(field_name, Map.get(opts, :options, []))
    build_errors(errors)
  end
  def build_control(Ecto.Date, resource, opts, model_name, field_name, _ext_name, errors) do
    %{name: model_name, model: resource, id: model_name, class: "form-control"}
    |> date_select(field_name, Map.get(opts, :options, []))
    build_errors(errors)
  end
  def build_control(Ecto.Time, resource, opts, model_name, field_name, _ext_name, errors) do
    %{name: model_name, model: resource, id: model_name, class: "form-control"}
    |> time_select(field_name, Map.get(opts, :options, []))
    build_errors(errors)
  end

  def build_control(:text, resource, opts, model_name, field_name, ext_name, errors) do
    value = Map.get(resource, field_name, "") |> escape_value
    options = opts
    |> Map.put(:class, "form-control")
    |> Map.put_new(:name, "#{model_name}[#{field_name}]")
    |> Map.put_new(:id, ext_name)
    |> Map.delete(:display)
    |> Map.to_list
    Xain.textarea value, options
    build_errors(errors)
  end

  def build_control(type, resource, opts, model_name, field_name, ext_name, errors) do
    {field_type, value} = if type |> Kernel.to_string |> String.ends_with?(".Type") do
      val = Map.get(resource, field_name, %{}) || %{}
      {:file, Map.get(val, :filename, "")}
    else
      {:text, Map.get(resource, field_name, "")}
    end
    value = ExAdmin.Render.to_string(value)
    Map.put_new(opts, :type, field_type)
    |> Map.put(:class, "form-control")
    |> Map.put_new(:maxlength, "255")
    |> Map.put_new(:name, "#{model_name}[#{field_name}]")
    |> Map.put_new(:id, ext_name)
    |> Map.put_new(:value, value |> escape_value)
    |> Map.delete(:display)
    |> Map.to_list
    |> Xain.input
    build_errors(errors)
  end

  def datetime_select(form, field_name, opts \\ []) do
    value = value_from(form, field_name)

    builder =
      Keyword.get(opts, :builder) || fn b ->
        date_builder(b, opts)
        span ".date-time-separator"
        # text " &mdash; "
        time_builder(b, opts)
      end

    builder.(datetime_builder(form, field_name, date_value(value), time_value(value), opts))
  end

  def date_select(form, field_name, opts \\ []) do
    value   = Keyword.get(opts, :value, value_from(form, field_name) || Keyword.get(opts, :default))
    builder = Keyword.get(opts, :builder) || &date_builder(&1, opts)
    builder.(datetime_builder(form, field_name, date_value(value), nil, opts))
  end

  defp date_builder(b, _opts) do
    b.(:year, [])
    span(".date-separator")
    b.(:month, [])
    span(".date-separator")
    b.(:day, [])
  end

  defp date_value(%{"year" => year, "month" => month, "day" => day}),
    do: %{year: year, month: month, day: day}
  defp date_value(%{year: year, month: month, day: day}),
    do: %{year: year, month: month, day: day}

  defp date_value({{year, month, day}, _}),
    do: %{year: year, month: month, day: day}
  defp date_value({year, month, day}),
    do: %{year: year, month: month, day: day}

  defp date_value(nil),
    do: %{year: nil, month: nil, day: nil}
  defp date_value(other),
    do: raise(ArgumentError, "unrecognized date #{inspect other}")

  def time_select(form, field, opts \\ []) do
    value   = Keyword.get(opts, :value, value_from(form, field) || Keyword.get(opts, :default))
    builder = Keyword.get(opts, :builder) || &time_builder(&1, opts)
    builder.(datetime_builder(form, field, nil, time_value(value), opts))
  end

  defp time_builder(b, opts) do
    b.(:hour, [])
    span ".time-separator"
    b.(:min, [])

    if Keyword.get(opts, :sec) do
      span ".time-separator"
      b.(:sec, [])
    end
  end

  defp time_value(%{"hour" => hour, "min" => min} = map),
    do: %{hour: hour, min: min, sec: Map.get(map, "sec", 0)}
  defp time_value(%{hour: hour, min: min} = map),
    do: %{hour: hour, min: min, sec: Map.get(map, :sec, 0)}

  defp time_value({_, {hour, min, sec, _msec}}),
    do: %{hour: hour, min: min, sec: sec}
  defp time_value({hour, min, sec, _mseg}),
    do: %{hour: hour, min: min, sec: sec}
  defp time_value({_, {hour, min, sec}}),
    do: %{hour: hour, min: min, sec: sec}
  defp time_value({hour, min, sec}),
    do: %{hour: hour, min: min, sec: sec}

  defp time_value(nil),
    do: %{hour: nil, min: nil, sec: nil}
  defp time_value(other),
    do: raise(ArgumentError, "unrecognized time #{inspect other}")

  @months [
    {"January", "1"},
    {"February", "2"},
    {"March", "3"},
    {"April", "4"},
    {"May", "5"},
    {"June", "6"},
    {"July", "7"},
    {"August", "8"},
    {"September", "9"},
    {"October", "10"},
    {"November", "11"},
    {"December", "12"},
  ]

  map = &Enum.map(&1, fn i ->
    i = Integer.to_string(i)
    {String.rjust(i, 2, ?0), i}
  end)
  @days   map.(1..31)
  @hours  map.(0..23)
  @minsec map.(0..59)

  defp datetime_builder(form, field, date, time, parent) do
    id   = Keyword.get(parent, :id, id_from(form, field))
    name = Keyword.get(parent, :name, name_from(form, field))

    fn
      :year, opts when date != nil ->
        {year, _, _}  = :erlang.date()
        {value, opts} = datetime_options(:year, year-5..year+5, id, name, parent, date, opts)
        build_select(:datetime, :year, value, opts)
      :month, opts when date != nil ->
        {value, opts} = datetime_options(:month, @months, id, name, parent, date, opts)
        build_select(:datetime, :month, value, opts)
      :day, opts when date != nil ->
        {value, opts} = datetime_options(:day, @days, id, name, parent, date, opts)
        build_select(:datetime, :day, value, opts)
      :hour, opts when time != nil ->
        {value, opts} = datetime_options(:hour, @hours, id, name, parent, time, opts)
        build_select(:datetime, :hour, value, opts)
      :min, opts when time != nil ->
        {value, opts} = datetime_options(:min, @minsec, id, name, parent, time, opts)
        build_select(:datetime, :min, value, opts)
      :sec, opts when time != nil ->
        {value, opts} = datetime_options(:sec, @minsec, id, name, parent, time, opts)
        build_select(:datetime, :sec, value, opts)
    end
  end

  defp build_select(_name, _type, value, opts) do
    value = if Range.range? value do
      Enum.map value, fn(x) ->
        val = Integer.to_string x
        {val,val}
      end
    else
      value
    end
    select "", [{:class, "form-control date-time"} |opts] do
      current_value = "#{opts[:value]}"
      Enum.each value, fn({k,v}) ->
        selected = if v == current_value, do: [selected: "selected"], else: []
        option k, [{:value, v}| selected]
      end
    end
  end

  defp datetime_options(type, values, id, name, parent, datetime, opts) do
    opts = Keyword.merge Keyword.get(parent, type, []), opts
    suff = Atom.to_string(type)

    {value, opts} = Keyword.pop(opts, :options, values)

    {value,
      opts
      |> Keyword.put_new(:id, id <> "_" <> suff)
      |> Keyword.put_new(:name, name <> "[" <> suff <> "]")
      |> Keyword.put_new(:value, Map.get(datetime, type))}
  end

  defp value_from(%{model: resource}, field_name) do
    Map.get(resource, field_name, "")
  end

  defp id_from(%{id: id}, field),
    do: "#{id}_#{field}"
  defp id_from(name, field) when is_atom(name),
    do: "#{name}_#{field}"

  defp name_from(%{name: name}, field),
    do: "#{name}[#{field}]"
  defp name_from(name, field) when is_atom(name),
    do: "#{name}[#{field}]"

  @doc false
  def build_has_many_fieldset(conn, res, fields, orig_inx, ext_name, field_name, field_field_name, model_name, errors) do
    theme_module(conn, Form).theme_build_has_many_fieldset(conn, res, fields,
        orig_inx, ext_name, field_name, field_field_name, model_name, errors)
  end

  @doc false
  def get_label(field_name, opts) do
    cond do
      Map.get(opts, :type) in ["hidden", :hidden] ->
        :none
      Map.get(opts, :display) ->
        {:hidden, Map.get(opts, :label, field_name) }
      Map.get(opts, :ajax) ->
        {:ajax, Map.get(opts, :label, field_name)}
      true ->
        Map.get opts, :label, field_name
    end
  end

  defp new_record_name(field_name) do
    name = field_name
    |> Atom.to_string
    |> Inflex.singularize
    |> String.replace(" ", "_")
    |> String.upcase
    "NEW_#{name}_RECORD"
  end

  # def build_actions_block(conn, model_name, mode) do
  #   display_name = ExAdmin.Utils.displayable_name_singular conn
  #   label = if mode == :new, do: "Create", else: "Update"
  #   div ".box-footer" do
  #     Xain.input ".btn.btn-primary", name: "commit", type: :submit, value: escape_value("#{label} #{humanize display_name}")
  #     a(".btn.btn-default.btn-cancel Cancel", href: admin_resource_path(conn, :index))
  #   end
  # end

  def escape_value(nil), do: nil
  def escape_value(value) when is_map(value), do: value
  def escape_value(value) do
    Phoenix.HTML.html_escape(value) |> elem(1)
  end

  @doc false
  def build_field_errors(conn, field_name) do
    conn.private
    |> Map.get(:phoenix_flash, %{})
    |> Map.get("inline_error", [])
    |> get_errors(field_name)
    |> Enum.reduce("", fn(error, acc) ->
      acc <> """
      <p class="inline-errors">#{error_messages error}</p>
      """
    end)
  end

  @doc false
  def default_form_view(conn, resource, params) do
    case conn.assigns.defn do
      nil ->
        throw :invalid_route
      %{__struct__: _} = defn ->
        columns = defn.resource_model.__schema__(:fields)
        |> Enum.filter(&(not &1 in [:id, :inserted_at, :updated_at]))
        |> Enum.map(&(build_item resource, defn, &1))
        |> Enum.filter(&(not is_nil(&1)))
        items = [%{type: :inputs, name: "", inputs: columns, opts: []}]
        Module.concat(var!(conn).assigns.theme, Form).build_form(
          conn, resource, items, params, false)
    end
  end

  defp binary_tuple?([]), do: false
  defp binary_tuple?(collection) do
    Enum.all?(collection, &(is_binary(&1) or (is_tuple(&1) and (tuple_size(&1) == 2))))
  end

  def required_abbr(true) do
    abbr ".required *", title: "required"
  end
  def required_abbr(_), do: ""

  def get_required(field_name, %{required: required}) do
    if field_name in required, do: true, else: false
  end
  def get_required(_, _), do: false

  @doc false
  def extra_javascript(model_name, param, attr) do
    {"var extra = $('##{model_name}_#{attr}').val();\n", "&#{param}='+extra+'"}
  end

  @doc false
  def get_errors(nil, _field_name), do: nil
  def get_errors(errors, field_name) do
    Enum.reduce errors, [], fn({k, v}, acc) ->
      if k == field_name, do: [v | acc], else: acc
    end
  end

  @doc false
  def build_errors(nil), do: nil
  def build_errors(errors) do
    for error <- errors do
      theme_module(Form).build_form_error(error)
    end
    errors
  end

  @doc false
  def error_messages(:unique), do: "has already been taken"
  def error_messages(:invalid), do: "has to be valid"
  def error_messages({:too_short, min}), do: "must be longer than #{min - 1}"
  def error_messages({:must_match, field}), do: "must match #{humanize field}"
  def error_messages(:format), do: "has incorrect format"
  def error_messages({msg, opts}) when is_binary(msg) do
    count = if is_integer(opts[:count]), do: opts[:count], else: 0
    String.replace(msg, "%{count}", Integer.to_string(count))
  end
  def error_messages(other) when is_binary(other), do: other
  def error_messages(other), do: "error: #{inspect other}"
end
