=begin rdoc
===FeatureManager

Provides the necessary controller level logic for enabling/disabling applications features on the fly.
The default 'invalid feature access' behaviour is to raise an Authorization error using base_auth.
You can customize the behaviour by providing your own handlers.

Note that the low level infrastructure for tracking the 'enabled' state of the feature
(like storing using ActiveRecord) has to be maintained by the application itself.

This plugin provides only *controller* level authorization for features. Any access to the feature
through one of the controllers/actions will be guarded. But, other references to the feautre
must be conditionally *disabled* by the application.

===Usage

*Register* the features in your application as follows

 class ApplicationController < ActionController::Base
   # 'File sharing' feautre
   add_feature('File sharing', [:files, :file_comments])
   add_feature('Wiki', [:wiki], [:controller => :users, :action => :my_pages])
 end

Enable the features that you want to use by calling enable_features in your controller
enable_features(['Wiki']) # This enabled features list may come from models, session, etc.,

Thats it! Now when someone accesses any of the pages that is related to file sharing feature,
it will result in an authorization error.

If you want to handle the invalid access gracefully, just override the 'handle_invalid_feature_access'
method in your controller

 def handle_invalid_feature_access(feature_name)
   flash[:error] = "Sorry. #{feature_name} feature is not enabled"
   redirect_to some_path
 end

Copyright (c) 2009 Vikram Venkatesan (vikram@chronus.com)

=end

module FeatureManager
  #  Array of FeatureDefinitions of _all_ features that are defined for the application
  attr_accessor :enabled_features

  def self.included(base)
    base.class_eval do
      # The features are static, and hence have them as class attributes
      class_inheritable_accessor :all_features
      extend ClassMethods
    end
  end

  module ClassMethods
    # Adds a feature to the application
    #
    # Params:
    # * <tt>identifier</tt> : the identifier of the feature, typically the feature name.
    # * <tt>controllers</tt> : Array of names of controllers which are _completely_ related to the
    #   feature. Say, the controller 'files' (i.e., FilesController) for feature called
    #   'files'.
    # * <tt>other_actions</tt> : Any other actions outside those in <i>controllers</i> that are also
    #   related to this feature. An Array of the form
    #
    #     [{:controller => 'some_controller', :actions => ['action_1', 'action_2']},
    #     {:controller => 'another_controller', :actions => 'single_action'}
    #     ]
    #
    def add_feature(identifier, controllers, other_actions = nil)
      definition = FeatureDefinition.new
      definition.identifier = identifier
      definition.controllers = controllers.collect(&:to_sym)
      definition.other_actions = other_actions
      self.all_features ||= []
      self.all_features << definition
    end
  end

  # Represents a feature in the application.
  class FeatureDefinition
    # the name of the feature
    attr_accessor :identifier

    # Array of names of controllers which are _completely_ related to the feature. Say, the
    # controller 'articles' (i.e., ArticlesController) for feature called 'Articles'.
    attr_accessor :controllers

    # Any other actions outside those in <i>controllers</i> that are also related to this feature.
    # An Array of the form
    #   [{:controller => 'some_controller', :actions => ['action_1', 'action_2']},
    #    {:controller => 'another_controller', :actions => 'single_action'}
    #   ]
    attr_accessor :other_actions

    # Returns whether the request represented by the controller and the action are covered under
    # this feature.
    def includes_action?(controller, action)
      value = self.controllers.collect(&:to_s).include?(controller.to_s)
      return value if value

      (self.other_actions || []).each do |act|
        value ||= (act[:controller] == controller && act[:action] == action)
      end

      return value
    end
  end

  protected
  
  # Returns the name of the feature that is being accessed in the current request.
  def feature_accessed
    self.all_features.each do |feature|
      return feature.identifier if feature.includes_action?(params[:controller], params[:action])
    end

    return nil
  end

  # Enables the features with the names given in <i>feature_names</i>
  def enable_features(feature_names)
    self.enabled_features = feature_names
  end

  # Checks whether the current request is allowed, given the enabled features list set through
  # <i>enable_features</i>.
  def check_feature_access
    cur_feature = feature_accessed
    return unless cur_feature # Not one of the feature pages. Nothing to check.

    unless self.enabled_features.include?(cur_feature)
      return handle_invalid_feature_access(cur_feature)
    end
  end

  # Raises an authorization error. Override in your controller if you want to handle this
  # differently.
  def handle_invalid_feature_access(feature_name)
    # base_auth plugin is needed for raising invalid feature access errors.
    require 'base_auth'

    deny! :exec => lambda {true}
  end
end
