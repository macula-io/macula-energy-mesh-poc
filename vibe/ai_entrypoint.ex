defmodule Vibe.AIEntrypoint do
  @moduledoc """
  AI Entrypoint for the Reckon ecosystem.
  This module serves as a central reference point for AI agents, providing information about
  documentation locations and application paths within the Reckon ecosystem.
  """

  @doc """
  Documentation and Implementation Guide Locations
  """
  def documentation_paths do
    %{
      primary_docs: "~/work/github.com/reckon-db-org/reckon_docs/",
      behavior_guides: "~/work/github.com/reckon-db-org/reckon_docs/behavior/",
      implementation_guides: "~/work/github.com/reckon-db-org/reckon_docs/implementation/",
      configuration_guides: "~/work/github.com/reckon-db-org/reckon_docs/configuration/",
      deployment_guides: "~/work/github.com/reckon-db-org/reckon_docs/deployment/"
    }
  end

  @doc """
  Base Applications and Libraries
  Essential components and foundational libraries of the system
  """
  def base_applications do
    %{
      ex_esdb: %{
        location: "~/work/github.com/beam-campus/ex-esdb/package/",
        synonyms: ["ExESDBServer", ":ex_esdb"],
        description: "Core EventStoreDB interface"
      },
      ex_esdb_gater: %{
        location: "~/work/github.com/beam-campus/ex-esdb-gater/system/",
        synonyms: ["ExESDBGater", ":ex_esdb_gater", "ExESDB Gateway"],
        description: "EventStoreDB Gateway service"
      },
      ex_esdb_commanded: %{
        location: "~/work/github.com/beam-campus/ex-esdb-commanded-adapter/package/",
        synonyms: ["EsESDB Commanded Adapter", ":ex_esdb_commanded"],
        description: "Commanded adapter for EventStoreDB"
      },
      bc_utils: %{
        location: "~/work/github.com/beam-campus/bc-utils/package/",
        synonyms: ["BCUtils", ":bc_utils"],
        description: "Beam Campus utility library"
      },
      bc_apis: %{
        location: "~/work/github.com/beam-campus/bc_apis/package/",
        synonyms: ["BCApis", ":bc_apis"],
        description: "Beam Campus API library"
      }
    }
  end

  @doc """
  Reckon Applications
  Main applications in the Reckon ecosystem
  """
  def reckon_applications do
    %{
      reckon_portal: %{
        location: "~/work/github.com/reckon-db-org/reckon_portal/",
        synonyms: [":reckon_portal", "The Reckon Portal application(s)"],
        description: "The Reckon Portal application(s)"
      },
      reckon_admin: %{
        location: "~/work/github.com/reckon-db-org/reckon_admin/",
        synonyms: [":reckon_admin", "The Reckon ExESDB Administration application"],
        description: "The Reckon ExESDB Administration application"
      },
      reckon_community: %{
        location: "~/work/github.com/reckon-db-org/reckon_community/",
        synonyms: [":reckon_community", "The Reckon Community application(s)"],
        description: "The Reckon Community application(s)"
      },
      reckon_aether: %{
        location: "~/work/github.com/reckon-db-org/reckon_aether/",
        synonyms: [":reckon_aether", "The Reckon Aether application(s)"],
        description: "The Reckon Aether application(s)"
      },
      greenhouse_tycoon: %{
        location: "~/work/github.com/reckon-db-org/greenhouse_tycoon/",
        synonyms: [":greenhouse_tycoon", "The Reckon 'Greenhouse Tycoon' Demo application"],
        description: "The Reckon 'Greenhouse Tycoon' Demo application"
      },
      poll_master: %{
        location: "~/work/github.com/reckon-db-org/poll_master/",
        synonyms: [":poll_master", "The Reckon 'Poll Master' Demo Application"],
        description: "The Reckon 'Poll Master' Demo Application"
      },
      reckon_identity: %{
        location: "~/work/github.com/reckon-db-org/reckon_identity/",
        synonyms: [":reckon_identity", "The Reckon Identity Management System"],
        description: "The Reckon Identity Management System for user registration, activation and basic activity/session/usage management"
      }
    }
  end

  @doc """
  Register a new application in the Reckon ecosystem.
  This function should be called when new applications are added.
  """
  def register_application(name, location, synonyms, description) do
    # This is a placeholder for the registration logic
    # In a real implementation, this would update the module or a persistent store
    {:ok, {name, location, synonyms, description}}
  end

  @doc """
  Get all known applications and their metadata
  """
  def all_applications do
    %{
      base: base_applications(),
      reckon: reckon_applications()
    }
  end
end
