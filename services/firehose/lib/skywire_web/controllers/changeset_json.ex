defmodule SkywireWeb.ChangesetJSON do
  @doc """
  Renders a changeset errors.
  """
  def error(%{changeset: changeset}) do
    # When encoded, the changeset returns its errors
    # as a JSON object, for example:
    #
    # {
    #   "errors": {
    #     "email": [
    #       "can't be blank"
    #     ]
    #   }
    # }
    %{errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)}
  end

  defp translate_error({msg, opts}) do
    # You can make use of gettext to translate error messages by
    # initializing the translator at the top of the file:
    #
    #     import SkywireWeb.Gettext
    #
    # In order to use the macro:
    #
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # Because the error messages we show in our forms and APIs
    # are defined inside Ecto, we need to translate them dynamically.
    # This requires us to call the Gettext module passing our gettext
    # backend as first argument.
    #
    # Note we use the "errors" domain, which means translations
    # should be written to the errors.po file. The :count option is
    # set by Ecto and indicates we should also apply plural rules.
    if count = opts[:count] do
      Gettext.dngettext(SkywireWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(SkywireWeb.Gettext, "errors", msg, opts)
    end
  end
end
