defmodule Absinthe.Type.Interface do

  @moduledoc """
  A defined interface type that represent a list of named fields and their
  arguments.

  Fields on an interface have the same rules as fields on an
  `Absinthe.Type.Object`.

  If an `Absinthe.Type.Object` lists an interface in its `:interfaces` entry, it
  it guarantees that it defines the same fields and arguments that the
  interface does.

  Because sometimes it's for the interface to determine the implementing type of
  a resolved object, you must either:

  * Provide a `:resolve_type` function on the interface
  * Provide a `:is_type_of` function on each implementing type

  ```
  @absinthe :type
  def named_entity do
    %Type.Interface{
      fields: fields(
        name: [type: :string]
      ),
      resolve_type: fn
        %{age: _}, _ -> {:ok, :person}
        %{employee_count: _}, _ -> {:ok, :business}
        _ -> :error
      end
    }
  end

  @absinthe :type
  def person do
    %Type.Object{
      fields: fields(
        name: [type: :string],
        age: [type: :string]
      ),
      interfaces: [:named_entity]
    }
  end

  @absinthe :type
  def business do
    %Type.Object{
      fields: fields(
        name: [type: :string],
        employee_count: [type: :integer]
      ),
      interfaces: [:named_entity]
    }
  end
  ```

  * `:name` - The name of the interface type. Should be a TitleCased `binary`. Set automatically when using `@absinthe :type` from `Absinthe.Type.Definitions`.
  * `:description` - A nice description for introspection.
  * `:fields` - A map of `Absinthe.Type.Field` structs. See `Absinthe.Type.Definitions.fields/1` and
  * `:args` - A map of `Absinthe.Type.Argument` structs. See `Absinthe.Type.Definitions.args/1`.
  * `:resolve_type` - A function used to determine the implementing type of a resolved object. See also `Absinthe.Type.Object`'s `:is_type_of`.

  The `:resolve_type` function will be passed two arguments; the object whose type needs to be identified, and the `Absinthe.Execution` struct providing the full execution context.

  The `:reference` key is for internal use.

  """

  use Absinthe.Introspection.Kind

  alias Absinthe.Type
  alias Absinthe.Execution
  alias Absinthe.Schema

  @type t :: %{name: binary, description: binary, fields: map, resolve_type: ((any, Absinthe.Execution.t) -> atom | nil), reference: Type.Reference.t}
  defstruct name: nil, description: nil, fields: nil, resolve_type: nil, reference: nil

  def build(identifier, blueprint) do
    fields = Type.Field.build_map_ast(blueprint[:fields] || [])
    quote do
      %unquote(__MODULE__){
        name: unquote(blueprint[:name]),
        fields: unquote(fields),
        resolve_type: unquote(blueprint[:resolve_type]),
        description: @absinthe_doc,
        reference: %{
          module: __MODULE__,
          identifier: unquote(identifier),
          location: %{
            file: __ENV__.file,
            line: __ENV__.line
          }
        }
      }
    end
  end

  @spec resolve_type(Type.Interface.t, any, Execution.Field.t) :: Type.t | nil
  def resolve_type(%{resolve_type: nil, reference: %{identifier: ident}}, obj, %{schema: schema}) do
    implementors = Schema.implementors(schema, ident)
    Enum.find(implementors, fn
      %{is_type_of: nil} ->
        false
      type ->
        type.is_type_of.(obj)
    end)
  end
  def resolve_type(%{resolve_type: resolver}, obj, %{schema: schema} = env) do
    case resolver.(obj, env) do
      nil ->
        nil
      ident when is_atom(ident) ->
        Schema.lookup_type(schema, ident)
    end
  end

  @doc """
  Whether the interface (or implementors) are correctly configured to resolve
  objects.
  """
  @spec type_resolvable?(Schema.t, t) :: boolean
  def type_resolvable?(schema, %{resolve_type: nil} = iface) do
    Schema.implementors(schema, iface)
    |> Enum.all?(&(&1.is_type_of))
  end
  def type_resolvable?(_, %{resolve_type: _}) do
    true
  end

  @spec implements?(Type.Interface.t, Type.Object.t) :: boolean
  def implements?(interface, type) do
    # Convert the submap into a list of key-value pairs where each key
    # is a list representing the keypath of its corresponding value.
    flatten_with_list_keys(interface.fields)
    # Check that every keypath has the same value in both maps
    # (assumes that `nil` is not a legitimate value)
    |> Enum.all?(fn
      {keypath, val} when val != nil ->
        flat = keypath |> List.flatten
        ignore_implementing_keypath?(flat) || (safe_get_in(type.fields, flat) == val)
      {_keypath, nil} ->
        true
    end)
  end

  # Try to get a value, ignoring errors
  @spec safe_get_in(any, list) :: any
  defp safe_get_in(target, keypath) do
    try do
      get_in(target, keypath)
    rescue
      FunctionClauseError ->
        nil
    end
  end

  @ignore [:description]
  defp ignore_implementing_keypath?(keypath) when is_list(keypath) do
    keypath
    |> List.last
    |> ignore_implementing_keypath?
  end
  defp ignore_implementing_keypath?(keypath) when is_atom(keypath) do
    Enum.member?(@ignore, keypath)
  end

  defp flatten_with_list_keys(map) do
    Enum.flat_map(Map.to_list(map), fn
      {:__struct__, _} ->
        []
      {key, map} when is_map(map) ->
        for {subkey, val} <- flatten_with_list_keys(map), do: {[key | [subkey]], val}
      other ->
        [other]
    end)
  end

end
