<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <!-- CDATA wrappers will be removed from all properties except the ones specified here-->
  <xsl:output method="xml" omit-xml-declaration="yes" cdata-section-elements="html_code method_code sqlserver_body stylesheet query class_structure report_query xsl_stylesheet"/>
  <xsl:variable name="systemProperties">|behavior|classification|config_id|created_by_id|created_on|css|current_state|generation|history_id|id|is_current|is_released|keyed_name|release_date|effective_date|locked_by_id|major_rev|managed_by_id|minor_rev|modified_by_id|modified_on|new_version|not_lockable|owned_by_id|permission_id|related_id|sort_order|source_id|state|itemtype|superseded_date|team_id|</xsl:variable>
  <xsl:template match="/">
    <xsl:apply-templates select="*[local-name()='Envelope']"/>
  </xsl:template>
  <xsl:template match="*[local-name()='Envelope']">
    <xsl:apply-templates select="*[local-name()='Body']"/>
  </xsl:template>
  <xsl:template match="*[local-name()='Body']">
    <xsl:apply-templates select="Result"/>
  </xsl:template>
  <xsl:template match="Result">
    <xsl:apply-templates select="Item" mode="first"/>
  </xsl:template>
  <xsl:template match="Item" mode="first">
    <AML>
      <xsl:copy>
        <xsl:copy-of select="@type"/>
        <xsl:copy-of select="@id"/>
        <xsl:attribute name="action">add</xsl:attribute>
        <xsl:copy-of select="@dependencyLevel"/>
        <xsl:apply-templates/>
      </xsl:copy>
      <!-- Find system properties that have been modified -->
      <xsl:if test="@type='ItemType'">
        <xsl:apply-templates mode="fix" select="."/>
      </xsl:if>
      <xsl:if test="@type='RelationshipType'">
        <xsl:apply-templates mode="fix" select="relationship_id/Item[@type='ItemType']"/>
      </xsl:if>
      <!-- Check for ItemTypes that have no Views/Forms and delete the autogenerated ones -->
      <xsl:if test="@type='ItemType' and not(Relationships/Item[@type='View'])">
        <Item type="View" action="delete" where="source_id='{@id}'"/>
        <Item type="Form" action="delete" where="name='{name}'"/>
      </xsl:if>
      <xsl:if test="boolean(relationship_id/Item) and not(relationship_id/Item/Relationships/Item[@type='View'])">
        <Item type="View" action="delete" where="source_id='{relationship_id/Item/@id}'"/>
        <Item type="Form" action="delete" where="name='{relationship_id/Item/name}'"/>
      </xsl:if>
      <!-- Check for Fields that use a system property as the data source and correct them -->
      <xsl:apply-templates mode="fix" select="//Item[@type='Field'][contains($systemProperties,concat('|',propertytype_id/@keyed_name,'|'))]"/>
      <!-- Deal with circular Identity=>Member=>Identity references by importing Members after Identities  -->
      <xsl:apply-templates mode="fix" select="Relationships/Item[@type='Member']"/>
      <!-- Deal with circular ItemType=>Morphae=>ItemType references by importing Morphae after ItemTypes  -->
      <xsl:apply-templates mode="fix" select="Relationships/Item[@type='Morphae']"/>
    </AML>
  </xsl:template>
  <xsl:template match="//Item[@type='Property' ]/Relationships/Item[@type='Grid Event']/source_id">
    <xsl:if test="contains($systemProperties,concat('|',../../../name,'|'))">
      <source_id>
        <Item type="Property" action="get" select="id">
          <name>
            <xsl:value-of select="../../../name"/>
          </name>
          <source_id>
            <xsl:value-of select="../../../source_id"/>
          </source_id>
        </Item>
      </source_id>
    </xsl:if>
    <xsl:if test="not(contains($systemProperties,concat('|',../../../name,'|')))">
      <xsl:copy>
        <xsl:copy-of select="@*"/>
        <xsl:apply-templates/>
      </xsl:copy>
    </xsl:if>
  </xsl:template>
  <!-- Identities may be matched either by id or name - call the named template to decide -->
  <xsl:template match="Item[@type='Identity'][name(..)!='' and name(..)!='Result']">
    <xsl:call-template name="Identity">
      <xsl:with-param name="id">
        <xsl:value-of select="@id"/>
      </xsl:with-param>
      <xsl:with-param name="keyed_name">
        <xsl:value-of select="keyed_name"/>
      </xsl:with-param>
    </xsl:call-template>
  </xsl:template>
  <!-- Methods are versionable, so it's better to match them by name -->
  <xsl:template match="Item[@type='Method'][name(..)!='' and name(..)!='Result']">
    <Item type="Method" action="get" select="id">
      <name>
        <xsl:value-of select="name"/>
      </name>
    </Item>
  </xsl:template>
  <!-- Remove Members and Morphae - they are added later as part of a fix -->
  <xsl:template match="Item[@type='Member' or @type='Morphae']"/>
  <!-- Remove SolutionConfig Export Actions -->
  <xsl:template match="Item[@type='Item Action'][related_id/@keyed_name='SolutionConfig Export']"/>
  <!-- Remove RelationshipTypes from ItemType exports -->
  <xsl:template match="Item[@type='ItemType']/Relationships/Item[@type='RelationshipType']"/>
  <!-- Match related ItemTypes by ID -->
  <xsl:template match="related_id/Item[@type='ItemType']">
    <xsl:value-of select="@id"/>
  </xsl:template>
  <!-- Special handling for the propertytype_id field, which points to Property -->
  <xsl:template match="Item[@type='Field']/propertytype_id">
    <xsl:if test="not(contains($systemProperties,concat('|',Item[@type='Property']/name,'|')))">
      <xsl:copy>
        <xsl:copy-of select="@*"/>
        <xsl:choose>
          <xsl:when test="not(Item)">
            <xsl:value-of select="."/>
          </xsl:when>
          <xsl:otherwise>
            <xsl:value-of select="Item/@id"/>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:copy>
    </xsl:if>
  </xsl:template>
  <!-- Item properties that point to Method
 
 "method[..\Item\@type='Report'] or pre_action[..\Item\@type='Life Cycle Transition' ]  or
  post_action[..\Item\@type='Life Cycle Transition' ] or method[..\Item\@type='Action'] or on_complete[..\Item\@type='Action'] or  method[..\Item\@type='View'] "
  Item[(@type='Action' and (method or on_complete)) or (@type='Life Cycle Transition' and (pre_action or post_action)) or (@type='Report' and (method)) or (@type='View' and (method))]-->
  <xsl:template match="Item[@type='Report']/method">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <Item type="Method" action="get" select="id">
        <name>
          <xsl:value-of select="@keyed_name"/>
        </name>
      </Item>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="Item[@type='Life Cycle Transition']/pre_action">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <Item type="Method" action="get" select="id">
        <name>
          <xsl:value-of select="@keyed_name"/>
        </name>
      </Item>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="Item[@type='Life Cycle Transition']/post_action">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <Item type="Method" action="get" select="id">
        <name>
          <xsl:value-of select="@keyed_name"/>
        </name>
      </Item>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="Item[@type='Action']/method">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <Item type="Method" action="get" select="id">
        <name>
          <xsl:value-of select="@keyed_name"/>
        </name>
      </Item>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="Item[@type='Action']/on_complete">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <Item type="Method" action="get" select="id">
        <name>
          <xsl:value-of select="@keyed_name"/>
        </name>
      </Item>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="Item[@type='View']/method">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <Item type="Method" action="get" select="id">
        <name>
          <xsl:value-of select="@keyed_name"/>
        </name>
      </Item>
    </xsl:copy>
  </xsl:template>
  <!-- match="Item[(@type='Activity Template' and (escalate_to)) or (@type='Activity Template Assignment' and (escalate_to)) or (@type='Activity Template EMail' and (alternate_identity)) or (@type='Life Cycle Transition' and (role)) or (@type='View' or (role)) or (@type='Workflow Map' and (process_owner))]">
    -->
  <xsl:template match="Item[@type='View']/role">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:call-template name="Identity">
        <xsl:with-param name="id">
          <xsl:value-of select="."/>
        </xsl:with-param>
        <xsl:with-param name="keyed_name">
          <xsl:value-of select="@keyed_name"/>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="Item[@type='Activity Template']/escalate_to">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:call-template name="Identity">
        <xsl:with-param name="id">
          <xsl:value-of select="."/>
        </xsl:with-param>
        <xsl:with-param name="keyed_name">
          <xsl:value-of select="@keyed_name"/>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="Item[@type='Activity Template Assignment']/escalate_to">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:call-template name="Identity">
        <xsl:with-param name="id">
          <xsl:value-of select="."/>
        </xsl:with-param>
        <xsl:with-param name="keyed_name">
          <xsl:value-of select="@keyed_name"/>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="Item[@type='Activity Template EMail']/alternate_identity">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:call-template name="Identity">
        <xsl:with-param name="id">
          <xsl:value-of select="."/>
        </xsl:with-param>
        <xsl:with-param name="keyed_name">
          <xsl:value-of select="@keyed_name"/>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="Item[@type='Life Cycle Transition']/role">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:call-template name="Identity">
        <xsl:with-param name="id">
          <xsl:value-of select="."/>
        </xsl:with-param>
        <xsl:with-param name="keyed_name">
          <xsl:value-of select="@keyed_name"/>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:copy>
  </xsl:template>
  <xsl:template match="Item[@type='Workflow Map']/process_owner">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:call-template name="Identity">
        <xsl:with-param name="id">
          <xsl:value-of select="."/>
        </xsl:with-param>
        <xsl:with-param name="keyed_name">
          <xsl:value-of select="@keyed_name"/>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:copy>
  </xsl:template>
  <!-- Add action="add" to all Items that don't match another template -->
  <xsl:template match="Item">
    <xsl:copy>
      <xsl:copy-of select="@type"/>
      <xsl:copy-of select="@id"/>
      <xsl:attribute name="action">add</xsl:attribute>
      <xsl:apply-templates/>
    </xsl:copy>
  </xsl:template>
  <!-- Special handling for identities -->
  <xsl:template name="Identity">
    <xsl:param name="id"/>
    <xsl:param name="keyed_name"/>
    <xsl:variable name="identities">|World|Creator|Owner|Manager|Innovator Admin|Super User|</xsl:variable>
    <xsl:variable name="kn">|<xsl:value-of select="$keyed_name"/>|</xsl:variable>
    <xsl:choose>
      <xsl:when test="contains($identities,$kn)">
        <Item type="Identity" action="get" select="id">
          <name>
            <xsl:value-of select="$keyed_name"/>
          </name>
        </Item>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$id"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <!-- Eliminate system and is_keyed properties and from ItemType definitions -->
  <xsl:template match="Item[@type='Property'][is_keyed='1']"/>
  <xsl:template match="Item[@type='Property'][name='behavior']"/>
  <xsl:template match="Item[@type='Property'][name='classification']"/>
  <xsl:template match="Item[@type='Property'][name='config_id']"/>
  <xsl:template match="Item[@type='Property'][name='created_by_id']"/>
  <xsl:template match="Item[@type='Property'][name='created_on']"/>
  <xsl:template match="Item[@type='Property'][name='css']"/>
  <xsl:template match="Item[@type='Property'][name='current_state']"/>
  <xsl:template match="Item[@type='Property'][name='generation']"/>
  <xsl:template match="Item[@type='Property'][name='history_id']"/>
  <xsl:template match="Item[@type='Property'][name='id']"/>
  <xsl:template match="Item[@type='Property'][name='is_current']"/>
  <xsl:template match="Item[@type='Property'][name='is_released']"/>
  <xsl:template match="Item[@type='Property'][name='keyed_name']"/>
  <xsl:template match="Item[@type='Property'][name='locked_by_id']"/>
  <xsl:template match="Item[@type='Property'][name='major_rev']"/>
  <xsl:template match="Item[@type='Property'][name='managed_by_id']"/>
  <xsl:template match="Item[@type='Property'][name='minor_rev']"/>
  <xsl:template match="Item[@type='Property'][name='modified_by_id']"/>
  <xsl:template match="Item[@type='Property'][name='modified_on']"/>
  <xsl:template match="Item[@type='Property'][name='new_version']"/>
  <xsl:template match="Item[@type='Property'][name='not_lockable']"/>
  <xsl:template match="Item[@type='Property'][name='owned_by_id']"/>
  <xsl:template match="Item[@type='Property'][name='permission_id']"/>
  <xsl:template match="Item[@type='Property'][name='related_id']"/>
  <xsl:template match="Item[@type='Property'][name='sort_order']"/>
  <xsl:template match="Item[@type='Property'][name='source_id']"/>
  <xsl:template match="Item[@type='Property'][name='state']"/>
  <xsl:template match="Item[@type='Property'][name='itemtype']"/>
  <xsl:template match="Item[@type='Property'][name='effective_date'][../../is_versionable='1']"/>
  <xsl:template match="Item[@type='Property'][name='release_date'][../../is_versionable='1']"/>
  <xsl:template match="Item[@type='Property'][name='superseded_date'][../../is_versionable='1']"/>
  <xsl:template match="Item[@type='Property'][name='team_id']"/>
  <!-- Handle foreign properties -->
  <xsl:template match="Item[@type='Property'][data_type='foreign']/data_source">
    <xsl:variable name="data_source" select="../data_source"/>
    <data_source>
      <Item type="Property" action="get" select="id">
        <name>
          <xsl:value-of select="../../Item[@type='Property'][id=$data_source]/name"/>
        </name>
        <source_id>
          <xsl:value-of select="../source_id"/>
        </source_id>
      </Item>
    </data_source>
  </xsl:template>
  <xsl:template match="Item[@type='Property'][data_type='foreign']/foreign_property">
    <xsl:variable name="data_source" select="../data_source"/>
    <foreign_property>
      <Item type="Property" action="get" select="id">
        <keyed_name>
          <xsl:value-of select="../foreign_property/@keyed_name"/>
        </keyed_name>
        <source_id>
          <Item type="ItemType" action="get" select="id">
            <name>
              <xsl:value-of select="../../Item[@type='Property'][id=$data_source]/data_source/@name"/>
            </name>
          </Item>
        </source_id>
      </Item>
    </foreign_property>
  </xsl:template>
  <!-- Eliminate the system properties from all ItemTypes -->
  <xsl:template match="Item[@type!='RelationshipType']/behavior"/>
  <xsl:template match="cache_query"/>
  <xsl:template match="config_id"/>
  <xsl:template match="core"/>
  <xsl:template match="created_by_id"/>
  <xsl:template match="created_on"/>
  <xsl:template match="Item[@type!='Field' and @type!='Body']/css"/>
  <xsl:template match="current_state"/>
  <xsl:template match="generation"/>
  <xsl:template match="history_id"/>
  <xsl:template match="id"/>
  <xsl:template match="is_cached"/>
  <xsl:template match="is_current"/>
  <xsl:template match="is_released"/>
  <xsl:template match="keyed_name"/>
  <xsl:template match="locked_by_id"/>
  <xsl:template match="major_rev"/>
  <xsl:template match="minor_rev"/>
  <xsl:template match="modified_by_id"/>
  <xsl:template match="modified_on"/>
  <xsl:template match="new_version"/>
  <xsl:template match="not_lockable"/>
  <xsl:template match="permission_id"/>
  <xsl:template match="state"/>
  <xsl:template match="itemtype"/>
  <xsl:template match="release_date"/>
  <xsl:template match="effective_date"/>
  <xsl:template match="superseded_date"/>
  <xsl:template match="Item[@type='Property' and data_type!='item' ]/item_behavior"/>

  <!-- Remove empty Relationships tags -->
  <xsl:template match="Relationships[count(*)=0]"/>

  <!-- Fix for Fields that use system properties as the data source -->
  <xsl:template mode="fix" match="Item[@type='Field']">
    <xsl:copy>
      <xsl:copy-of select="@type"/>
      <xsl:copy-of select="@id"/>
      <xsl:attribute name="action">edit</xsl:attribute>
      <xsl:comment> Please note: this AML depends on the &quot;<xsl:value-of select="propertytype_id/Item/source_id/@keyed_name"/>&quot; ItemType. Please make sure it exists before running this. </xsl:comment>
      <propertytype_id>
        <Item type="Property" action="get" select="id">
          <name>
            <xsl:value-of select="propertytype_id/Item/name"/>
          </name>
          <source_id type="{propertytype_id/Item/source_id/@type}" keyed_name="{propertytype_id/Item/source_id/@keyed_name}">
            <xsl:value-of select="propertytype_id/Item/source_id"/>
          </source_id>
        </Item>
      </propertytype_id>
    </xsl:copy>
  </xsl:template>
  <!-- Special handling for the propertytype_id field, which points to Property -->
  <xsl:template mode="fix" match="Item[@type='Field']/propertytype_id">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:copy-of select="Item"/>
    </xsl:copy>
  </xsl:template>
  <!-- Second ItemType tag to deal with is_keyed and modified system properties -->
  <xsl:template mode="fix" match="Item[@type='ItemType']">
    <xsl:variable name="modifiedSystemProps" select="Relationships/Item[@type='Property'][name='behavior'][string(label)!='' or string(data_type)!='list' or string(stored_length)!='64' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='classification'][string(label)!='Classification' or string(data_type)!='string' or string(stored_length)!='512' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='config_id'][string(label)!='' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='created_by_id'][string(label)!='' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='created_on'][string(label)!='' or string(data_type)!='date' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='css'][string(label)!='' or string(data_type)!='text' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='current_state'][string(label)!='' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='generation'][string(label)!='' or string(data_type)!='integer' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='history_id'][string(label)!='History Id' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='id'][string(label)!='' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='is_current'][string(label)!='' or string(data_type)!='boolean' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0'] |
                                  Relationships/Item[@type='Property'][name='is_released'][string(label)!='Released' or string(data_type)!='boolean' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='keyed_name'][string(label)!='' or string(data_type)!='string' or string(stored_length)!='128' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='locked_by_id'][string(label)!='' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='major_rev'][string(label)!='' or string(data_type)!='string' or string(stored_length)!='8' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='managed_by_id'][string(label)!='' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='minor_rev'][string(label)!='' or string(data_type)!='string' or string(stored_length)!='8' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='modified_by_id'][string(label)!='' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='modified_on'][string(label)!='' or string(data_type)!='date' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='new_version'][string(label)!='' or string(data_type)!='boolean' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='not_lockable'][string(label)!='Not Lockable' or string(data_type)!='boolean' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='owned_by_id'][string(label)!='' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='permission_id'][string(label)!='' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='related_id'][string(label)!='' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='0' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='sort_order'][string(label)!='' or string(data_type)!='integer' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='source_id'][string(label)!='' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='state'][string(label)!='' or string(data_type)!='string' or string(stored_length)!='32' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] | 
                                  Relationships/Item[@type='Property'][name='effective_date'][../../is_versionable='1'][string(label)!='Effective Date' or string(data_type)!='date' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='release_date'][../../is_versionable='1'][string(label)!='Release Date' or string(data_type)!='date' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='superseded_date'][../../is_versionable='1'][string(label)!='Superseded Date' or string(data_type)!='date' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='0' or string(is_hidden2)!='0' or string(column_width)!='' or string(readonly)!='1' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][name='itemtype'][string(label)!='ItemType' or string(data_type)!='list' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] | 
                                  Relationships/Item[@type='Property'][name='team_id'][string(label)!='Team' or string(data_type)!='item' or string(stored_length)!='' or string(column_alignment)!='left' or string(is_hidden)!='1' or string(is_hidden2)!='1' or string(column_width)!='' or string(readonly)!='0' or string(is_keyed)!='0' or string(order_by)!=''] |
                                  Relationships/Item[@type='Property'][contains($systemProperties,concat('|',name,'|'))][Relationships[child::node()]]"/>

    <xsl:if test="count(Relationships/Item[@type='Property'][is_keyed='1'][not(contains($systemProperties,concat('|',name,'|')))]) > 0 or count($modifiedSystemProps) > 0">
      <xsl:copy>
        <xsl:copy-of select="@type"/>
        <xsl:copy-of select="@id"/>
        <xsl:attribute name="action">edit</xsl:attribute>
        <Relationships>
          <xsl:apply-templates mode="fix" select="Relationships/Item[@type='Property'][is_keyed='1'][not(contains($systemProperties,concat('|',name,'|')))]"/>
          <xsl:apply-templates mode="fix" select="$modifiedSystemProps"/>
        </Relationships>
      </xsl:copy>  
    </xsl:if>
  </xsl:template>
  <!-- Fix for system properties that have been modified  -->
  <!-- Properties with is_keyed='1' add with modified system properties, because there may be a situation such as in RT Field Event(source_id, related_id and field_event in a general index and this properties must be imported together) -->
  <xsl:template mode="fix" match="Item[@type='Property']">
    <xsl:copy>
      <xsl:copy-of select="@type"/>
      <xsl:choose>
        <xsl:when test="contains($systemProperties,concat('|',name,'|'))">
          <xsl:attribute name="action">edit</xsl:attribute>
          <xsl:attribute name="where">source_id='<xsl:value-of select="source_id"/>' and name='<xsl:value-of select="name"/>'</xsl:attribute>
        </xsl:when>
        <xsl:when test="is_keyed='1'">
          <xsl:copy-of select="@id"/>
          <xsl:attribute name="action">add</xsl:attribute>
        </xsl:when>
      </xsl:choose>
      <xsl:apply-templates/>
    </xsl:copy>
  </xsl:template>
  <!-- Fix to put Members at the end  -->
  <xsl:template mode="fix" match="Item[@type='Member']">
    <xsl:copy>
      <xsl:copy-of select="@type"/>
      <xsl:copy-of select="@id"/>
      <xsl:attribute name="action">add</xsl:attribute>
      <xsl:apply-templates/>
    </xsl:copy>
  </xsl:template>
  <!-- Fix for Morphae  -->
  <xsl:template mode="fix" match="Item[@type='Morphae']">
    <Item type="ItemType" id="{../../@id}" action="edit">
      <Relationships>
        <xsl:copy>
          <xsl:copy-of select="@type"/>
          <xsl:copy-of select="@id"/>
          <xsl:attribute name="action">add</xsl:attribute>
          <xsl:apply-templates/>
        </xsl:copy>
      </Relationships>
    </Item>
  </xsl:template>
  <!-- Copy all nodes that don't match another template (but remove CDATA wrappers) -->
  <xsl:template match="*">
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:apply-templates/>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>